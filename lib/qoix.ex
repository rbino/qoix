defmodule Qoix do
  @moduledoc """
  Qoix is an Elixir implementation of the [Quite OK Image](https://phoboslab.org/log/2021/11/qoi-fast-lossless-image-compression) format.
  """

  alias Qoix.Image
  use Bitwise

  @index_flag <<0::2>>
  @run_8_flag <<2::3>>
  @run_16_flag <<3::3>>
  @diff_8_flag <<2::2>>
  @diff_16_flag <<6::3>>
  @diff_24_flag <<14::4>>
  @color_flag <<15::4>>
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
  def encode(%Image{width: width, height: height, pixels: pixels}, opts \\ []) do
    with {:ok, channels} <- build_channels(opts),
         {:ok, colorspace} <- build_colorspace(opts) do
      chunks =
        pixels
        |> encode_pixels()
        |> IO.iodata_to_binary()

      # Return the final binary
      data =
        <<"qoif", width::32, height::32, channels::8, colorspace::8, chunks::binary,
          @padding::binary>>

      {:ok, data}
    end
  end

  defp build_channels(opts) do
    case Keyword.fetch(opts, :channels) do
      {:ok, value} when value == 3 or value == 4 ->
        {:ok, value}

      {:ok, _value} ->
        {:error, :invalid_channels}

      :error ->
        # No explicit channels indication, default to 4
        {:ok, 4}
    end
  end

  # TODO: just return 0 (which is sRGB) for now
  defp build_colorspace(_opts), do: {:ok, 0}

  defp encode_pixels(<<pixels::binary>>) do
    # Previous pixel is initialized to 0,0,0,255
    prev = <<0, 0, 0, 255>>
    run_length = 0
    # TODO: evaluate different data structures for this
    lut = for i <- 0..63, into: %{}, do: {i, <<0::32>>}
    acc = []

    do_encode(pixels, prev, run_length, lut, acc)
  end

  # Here we go with all the possible cases. Order matters due to pattern matching.

  # Maximum representable run_length, push out and start a new one
  defp do_encode(<<pixels::bits>>, prev, run_length, lut, acc)
       when run_length == 0x2020 do
    do_encode(pixels, prev, 0, lut, [acc | <<@run_16_flag::bits, map_run_16(run_length)::13>>])
  end

  # Same pixel as previous, consume and increase run_length
  defp do_encode(<<pixel::32, rest::bits>>, <<pixel::32>>, run_length, lut, acc) do
    do_encode(rest, <<pixel::32>>, run_length + 1, lut, acc)
  end

  # Since we didn't match the previous head, the pixel is different from the previous.
  # We don't have any ongoing run_length, so we just have to handle the pixel.
  defp do_encode(<<r::8, g::8, b::8, a::8, rest::bits>>, prev, 0, lut, acc) do
    pixel = <<r::8, g::8, b::8, a::8>>

    # XOR the values to calculate the LUT key
    lut_index = lut_index(r, g, b, a)

    {chunk, new_lut} =
      case Map.fetch(lut, lut_index) do
        {:ok, value} when value == pixel ->
          {<<@index_flag::bits, lut_index::6>>, lut}

        _ ->
          # Either we didn't find the value or it was different from our current pixel
          chunk = diff_or_color(pixel, prev)
          new_lut = Map.put(lut, lut_index, pixel)

          {chunk, new_lut}
      end

    do_encode(rest, pixel, 0, new_lut, [acc | chunk])
  end

  # For the same reason as above, the pixel is different from the previous.
  # Here we just emit the 13 bit run length and leave the pixel handling to the next recursion,
  # that will enter in the previous head.
  defp do_encode(<<pixels::bits>>, prev, run_length, lut, acc)
       when run_length > 32 do
    do_encode(pixels, prev, 0, lut, [acc | <<@run_16_flag::bits, map_run_16(run_length)::13>>])
  end

  # As above, but for a 5 bit run length.
  defp do_encode(<<pixels::bits>>, prev, run_length, lut, acc)
       when run_length > 0 do
    # Maximum representable run_length, push out and start a new one
    do_encode(pixels, prev, 0, lut, [acc | <<@run_8_flag::bits, map_run_8(run_length)::5>>])
  end

  # All pixels consumed, no ongoing run: just output the accumulator
  defp do_encode(<<>>, _prev, 0, _lut, acc) do
    acc
  end

  # All pixels consumed, pending 13 bit run: output the accumulator and the 13 bit run with its flag
  defp do_encode(<<>>, _prev, run_length, _lut, acc) when run_length > 32 do
    [acc | <<@run_16_flag::bits, map_run_16(run_length)::13>>]
  end

  # All pixels consumed, pending 5 bit run: output the accumulator and the 5 bit run with its flag
  defp do_encode(<<>>, _prev, run_length, _lut, acc) do
    [acc | <<@run_8_flag::bits, map_run_8(run_length)::5>>]
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
        <<@diff_8_flag::bits, map_range_2(dr)::2, map_range_2(dg)::2, map_range_2(db)::2>>

      # Diff 16
      da == 0 and in_range_5?(dr) and in_range_4?(dg) and in_range_4?(db) ->
        <<@diff_16_flag::bits, map_range_5(dr)::5, map_range_4(dg)::4, map_range_4(db)::4>>

      # Diff 24
      in_range_5?(dr) and in_range_5?(dg) and in_range_5?(db) and in_range_5?(da) ->
        <<@diff_24_flag::bits, map_range_5(dr)::5, map_range_5(dg)::5, map_range_5(db)::5,
          map_range_5(da)::5>>

      # Last resort, full color
      true ->
        {r?, r} = build_full_color_component(r, dr)
        {g?, g} = build_full_color_component(g, dg)
        {b?, b} = build_full_color_component(b, db)
        {a?, a} = build_full_color_component(a, da)

        <<@color_flag::bits, r?::bits, g?::bits, b?::bits, a?::bits, r::bits, g::bits, b::bits,
          a::bits>>
    end
  end

  defp lut_index(r, g, b, a) do
    # XOR r, g, b and a and return the result modulo 64
    r
    |> bxor(g)
    |> bxor(b)
    |> bxor(a)
    |> rem(64)
  end

  defp build_full_color_component(color_value, color_diff) do
    if color_diff == 0 do
      {@false_bit, <<>>}
    else
      {@true_bit, <<color_value::8>>}
    end
  end

  # Offset run lengths to exploit all the available ranges
  defp map_run_8(val), do: val - 1
  defp map_run_16(val), do: val - 33

  # Check if values can be represented with the various diff ranges
  defp in_range_2?(val), do: val >= -2 and val <= 1
  defp in_range_4?(val), do: val >= -8 and val <= 7
  defp in_range_5?(val), do: val >= -16 and val <= 15

  # Add the offset to recenter the different ranges to 0
  defp map_range_2(val), do: val + 2
  defp map_range_4(val), do: val + 8
  defp map_range_5(val), do: val + 16
end
