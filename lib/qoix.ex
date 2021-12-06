defmodule Qoix do
  @moduledoc """
  Qoix is an Elixir implementation of the [Quite OK Image](https://phoboslab.org/log/2021/11/qoi-fast-lossless-image-compression) format.
  """

  alias Qoix.Image
  use Bitwise

  @index_tag <<0::2>>
  @run_8_tag <<2::3>>
  @run_16_tag <<3::3>>
  @diff_8_tag <<2::2>>
  @diff_16_tag <<6::3>>
  @diff_24_tag <<14::4>>
  @color_tag <<15::4>>
  @true_bit <<1::1>>
  @false_bit <<0::1>>
  @padding <<0, 0, 0, 0>>

  @doc """
  Returns true if the binary appears to contain a valid QOI image.
  """
  def qoi?(<<"qoif", _width::32, _height::32, channels::8, _colorspace::8, _rest::binary>>)
      when channels == 3 or channels == 4 do
    true
  end

  def qoi?(_binary) do
    false
  end

  @doc """
  Encodes a `%Qoix.Image{}` using QOI, returning a binary with the encoded image.

  Returns `{:ok, encoded}` on success, `{:error, reason}` on failure.
  """
  def encode(%Image{width: width, height: height, pixels: pixels, format: format}, opts \\ [])
      when width > 0 and height > 0 and format in [:rgb, :rgba] and is_binary(pixels) do
    channels = channels(format)
    colorspace = colorspace(opts)

    chunks =
      pixels
      |> encode_pixels(format)
      |> IO.iodata_to_binary()

    # Return the final binary
    data =
      <<"qoif", width::32, height::32, channels::8, colorspace::8, chunks::binary,
        @padding::binary>>

    {:ok, data}
  end

  defp channels(:rgb), do: 3
  defp channels(:rgba), do: 4

  # TODO: just return 0 (which is sRGB) for now
  defp colorspace(_opts), do: 0

  defp encode_pixels(<<pixels::binary>>, format) when format == :rgb or format == :rgba do
    # Previous pixel is initialized to 0,0,0,255
    prev = <<0, 0, 0, 255>>
    run_length = 0
    lut = for i <- 0..63, into: %{}, do: {i, <<0::32>>}
    acc = []

    do_encode(pixels, format, prev, run_length, lut, acc)
  end

  # Here we go with all the possible cases. Order matters due to pattern matching.

  # Maximum representable run_length, push out and start a new one
  defp do_encode(<<pixels::bits>>, format, prev, run_length, lut, acc)
       when run_length == 0x2020 do
    acc = [acc | <<@run_16_tag::bits, map_run_16(run_length)::13>>]

    do_encode(pixels, format, prev, 0, lut, acc)
  end

  # Same RGBA pixel as previous, consume and increase run_length
  defp do_encode(<<pixel::32, rest::bits>>, :rgba = format, <<pixel::32>>, run_length, lut, acc) do
    do_encode(rest, format, <<pixel::32>>, run_length + 1, lut, acc)
  end

  # Same RGB pixel as previous, consume and increase run_length
  defp do_encode(<<pixel::24, rest::bits>>, :rgb = format, <<pixel::24>>, run_length, lut, acc) do
    do_encode(rest, format, <<pixel::24>>, run_length + 1, lut, acc)
  end

  # Since we didn't match the previous head, the pixel is different from the previous.
  # We don't have any ongoing run_length, so we just have to handle the pixel.
  defp do_encode(<<r::8, g::8, b::8, a::8, rest::bits>>, :rgba = format, prev, 0, lut, acc) do
    pixel = <<r::8, g::8, b::8, a::8>>

    {chunk, new_lut} = handle_non_running_pixel(pixel, prev, lut)
    acc = [acc | chunk]

    do_encode(rest, format, pixel, 0, new_lut, acc)
  end

  # As above, but for RGB
  defp do_encode(<<r::8, g::8, b::8, rest::bits>>, :rgb = format, prev, 0, lut, acc) do
    pixel = <<r::8, g::8, b::8, 255::8>>

    {chunk, new_lut} = handle_non_running_pixel(pixel, prev, lut)

    do_encode(rest, format, pixel, 0, new_lut, [acc | chunk])
  end

  # For the same reason as above, the pixel is different from the previous.
  # Here we just emit the 13 bit run length and leave the pixel handling to the next recursion,
  # that will enter in the previous head.
  defp do_encode(<<pixels::bits>>, format, prev, run_length, lut, acc)
       when run_length > 32 do
    acc = [acc | <<@run_16_tag::bits, map_run_16(run_length)::13>>]

    do_encode(pixels, format, prev, 0, lut, acc)
  end

  # As above, but for a 5 bit run length.
  defp do_encode(<<pixels::bits>>, format, prev, run_length, lut, acc)
       when run_length > 0 do
    acc = [acc | <<@run_8_tag::bits, map_run_8(run_length)::5>>]

    do_encode(pixels, format, prev, 0, lut, acc)
  end

  # All pixels consumed, no ongoing run: just output the accumulator
  defp do_encode(<<>>, _format, _prev, 0, _lut, acc) do
    acc
  end

  # All pixels consumed, pending 13 bit run: output the accumulator and the 13 bit run with its tag
  defp do_encode(<<>>, _format, _prev, run_length, _lut, acc) when run_length > 32 do
    [acc | <<@run_16_tag::bits, map_run_16(run_length)::13>>]
  end

  # All pixels consumed, pending 5 bit run: output the accumulator and the 5 bit run with its tag
  defp do_encode(<<>>, _format, _prev, run_length, _lut, acc) do
    [acc | <<@run_8_tag::bits, map_run_8(run_length)::5>>]
  end

  # Handle a pixel that is not part of a run, return a {chunk, updated_lut} tuple
  defp handle_non_running_pixel(<<r::8, g::8, b::8, a::8>> = pixel, prev, lut) do
    # XOR the values to calculate the LUT key
    lut_index = lut_index(r, g, b, a)

    case Map.fetch(lut, lut_index) do
      {:ok, <<^r::8, ^g::8, ^b::8, ^a::8>>} ->
        {<<@index_tag::bits, lut_index::6>>, lut}

      _ ->
        # Either we didn't find the value or it was different from our current pixel
        chunk = diff_or_color(pixel, prev)
        new_lut = Map.put(lut, lut_index, <<r, g, b, a>>)

        {chunk, new_lut}
    end
  end

  # Emit a diff or color chunk
  defp diff_or_color(<<r::8, g::8, b::8, a::8>> = _pixel, <<pr::8, pg::8, pb::8, pa::8>> = _prev) do
    # Compute pixel differences
    dr = r - pr
    dg = g - pg
    db = b - pb
    da = a - pa

    cond do
      # Diff 8
      da == 0 and in_range_2?(dr) and in_range_2?(dg) and in_range_2?(db) ->
        <<@diff_8_tag::bits, map_range_2(dr)::2, map_range_2(dg)::2, map_range_2(db)::2>>

      # Diff 16
      da == 0 and in_range_5?(dr) and in_range_4?(dg) and in_range_4?(db) ->
        <<@diff_16_tag::bits, map_range_5(dr)::5, map_range_4(dg)::4, map_range_4(db)::4>>

      # Diff 24
      in_range_5?(dr) and in_range_5?(dg) and in_range_5?(db) and in_range_5?(da) ->
        <<@diff_24_tag::bits, map_range_5(dr)::5, map_range_5(dg)::5, map_range_5(db)::5,
          map_range_5(da)::5>>

      # Last resort, full color
      true ->
        {r?, r} = color_bit_and_value(r, dr)
        {g?, g} = color_bit_and_value(g, dg)
        {b?, b} = color_bit_and_value(b, db)
        {a?, a} = color_bit_and_value(a, da)

        <<@color_tag::bits, r?::bits, g?::bits, b?::bits, a?::bits, r::bits, g::bits, b::bits,
          a::bits>>
    end
  end

  defp color_bit_and_value(color_value, color_diff) do
    if color_diff == 0 do
      {@false_bit, <<>>}
    else
      {@true_bit, <<color_value::8>>}
    end
  end

  @doc """
  Decodes a QOI image, returning an `%Image{}`.

  Returns `{:ok, %Image{}}` on success, `{:error, reason}` on failure.
  """
  def decode(<<encoded::binary>>) do
    # TODO: we ignore colorspace for now
    case encoded do
      <<"qoif", width::32, height::32, channels::8, _colorspace::8, chunks::binary>> ->
        format = format(channels)

        pixels =
          chunks
          |> decode_chunks(format)
          |> IO.iodata_to_binary()

        {:ok, %Image{width: width, height: height, pixels: pixels, format: format}}

      _ ->
        {:error, :invalid_qoi}
    end
  end

  defp format(3), do: :rgb
  defp format(4), do: :rgba

  defp decode_chunks(<<chunks::bits>>, format) do
    # Previous pixel is initialized to 0,0,0,255
    prev = <<0, 0, 0, 255>>
    lut = for i <- 0..63, into: %{}, do: {i, <<0::32>>}
    acc = []

    do_decode(chunks, format, prev, lut, acc)
  end

  # Let's decode

  # Final padding, we're done, return the accumulator
  defp do_decode(@padding, _format, _prev, _lut, acc) do
    acc
  end

  # Index: get the pixel from the LUT
  defp do_decode(<<@index_tag, index::6, rest::bits>>, format, _prev, lut, acc) do
    pixel = Map.fetch!(lut, index)
    out_pixel = maybe_drop_alpha(pixel, format)

    do_decode(rest, format, pixel, lut, [acc | out_pixel])
  end

  # Run 8: repeat previous pixel
  defp do_decode(<<@run_8_tag, count::5, rest::bits>>, format, prev, lut, acc) do
    pixels =
      maybe_drop_alpha(prev, format)
      |> :binary.copy(unmap_run_8(count))

    do_decode(rest, format, prev, lut, [acc | pixels])
  end

  # Run 16: repeat previous pixel
  defp do_decode(<<@run_16_tag, count::13, rest::bits>>, format, prev, lut, acc) do
    pixels =
      maybe_drop_alpha(prev, format)
      |> :binary.copy(unmap_run_16(count))

    do_decode(rest, format, prev, lut, [acc | pixels])
  end

  # Diff 8: reconstruct pixel from previous + diff
  defp do_decode(<<@diff_8_tag, dr::2, dg::2, db::2, rest::bits>>, format, prev, lut, acc) do
    <<pr, pg, pb, pa>> = prev
    r = pr + unmap_range_2(dr)
    g = pg + unmap_range_2(dg)
    b = pb + unmap_range_2(db)

    pixel = <<r, g, b, pa>>
    out_pixel = maybe_drop_alpha(pixel, format)

    do_decode(rest, format, pixel, update_lut(lut, pixel), [acc | out_pixel])
  end

  # Diff 16: reconstruct pixel from previous + diff
  defp do_decode(<<@diff_16_tag, dr::5, dg::4, db::4, rest::bits>>, format, prev, lut, acc) do
    <<pr, pg, pb, pa>> = prev
    r = pr + unmap_range_5(dr)
    g = pg + unmap_range_4(dg)
    b = pb + unmap_range_4(db)

    pixel = <<r, g, b, pa>>
    out_pixel = maybe_drop_alpha(pixel, format)

    do_decode(rest, format, pixel, update_lut(lut, pixel), [acc | out_pixel])
  end

  # Diff 24: reconstruct pixel from previous + diff
  defp do_decode(<<@diff_24_tag, dr::5, dg::5, db::5, da::5, rest::bits>>, format, prev, lut, acc) do
    <<pr, pg, pb, pa>> = prev
    r = pr + unmap_range_5(dr)
    g = pg + unmap_range_5(dg)
    b = pb + unmap_range_5(db)
    a = pa + unmap_range_5(da)

    pixel = <<r, g, b, a>>
    out_pixel = maybe_drop_alpha(pixel, format)

    do_decode(rest, format, pixel, update_lut(lut, pixel), [acc | out_pixel])
  end

  # Color: take full color values from chunk or prev depending on the bit flags
  defp do_decode(
         <<@color_tag, r?::1, g?::1, b?::1, a?::1, maybe_values_and_rest::bits>>,
         format,
         prev,
         lut,
         acc
       ) do
    <<pr, pg, pb, pa>> = prev

    r_size = r? * 8
    g_size = g? * 8
    b_size = b? * 8
    a_size = a? * 8

    <<maybe_r::size(r_size), maybe_g::size(g_size), maybe_b::size(b_size), maybe_a::size(a_size),
      rest::bits>> = maybe_values_and_rest

    r = value_or_previous(r? == 1, maybe_r, pr)
    g = value_or_previous(g? == 1, maybe_g, pg)
    b = value_or_previous(b? == 1, maybe_b, pb)
    a = value_or_previous(a? == 1, maybe_a, pa)

    pixel = <<r, g, b, a>>
    out_pixel = maybe_drop_alpha(pixel, format)

    do_decode(rest, format, pixel, update_lut(lut, pixel), [acc | out_pixel])
  end

  defp maybe_drop_alpha(pixel, :rgba), do: pixel
  defp maybe_drop_alpha(<<r::8, g::8, b::8, _a::8>>, :rgb), do: <<r::8, g::8, b::8>>

  defp value_or_previous(true = _value_present, value, _prev), do: value
  defp value_or_previous(false = _value_present, _value, prev), do: prev

  defp lut_index(r, g, b, a) do
    # XOR r, g, b and a and return the result modulo 64
    r
    |> bxor(g)
    |> bxor(b)
    |> bxor(a)
    |> rem(64)
  end

  defp update_lut(lut, <<r, g, b, a>>) do
    lut_index = lut_index(r, g, b, a)

    Map.put(lut, lut_index, <<r, g, b, a>>)
  end

  # Offset run lengths to exploit all the available ranges
  defp map_run_8(val), do: val - 1
  defp map_run_16(val), do: val - 33

  # Remove run lengths offsets to retrieve the original value
  defp unmap_run_8(val), do: val + 1
  defp unmap_run_16(val), do: val + 33

  # Check if values can be represented with the various diff ranges
  defp in_range_2?(val), do: val >= -2 and val <= 1
  defp in_range_4?(val), do: val >= -8 and val <= 7
  defp in_range_5?(val), do: val >= -16 and val <= 15

  # Add the offset to recenter the different ranges to 0
  defp map_range_2(val), do: val + 2
  defp map_range_4(val), do: val + 8
  defp map_range_5(val), do: val + 16

  # Remove the offset to recenter the different ranges to 0
  defp unmap_range_2(val), do: val - 2
  defp unmap_range_4(val), do: val - 8
  defp unmap_range_5(val), do: val - 16
end
