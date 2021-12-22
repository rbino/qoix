defmodule Qoix do
  @moduledoc """
  Qoix is an Elixir implementation of the [Quite OK Image format](https://qoiformat.org).
  """

  alias Qoix.Image
  use Bitwise

  @index_op <<0::2>>
  @diff_op <<1::2>>
  @luma_op <<2::2>>
  @run_op <<3::2>>
  @rgb_op <<254::8>>
  @rgba_op <<255::8>>
  @padding :binary.copy(<<0>>, 7) <> <<1>>
  @empty_lut for i <- 0..63, into: %{}, do: {i, <<0::32>>}

  @doc """
  Returns true if the binary appears to contain a valid QOI image.
  """
  @spec qoi?(binary) :: boolean
  def qoi?(<<"qoif", _width::32, _height::32, channels::8, cspace::8, _rest::binary>> = _binary)
      when channels in [3, 4] and cspace in [0, 1] do
    true
  end

  def qoi?(binary) when is_binary(binary) do
    false
  end

  @doc """
  Encodes a `%Qoix.Image{}` using QOI, returning a binary with the encoded image.

  Returns `{:ok, encoded}` on success, `{:error, reason}` on failure.
  """
  @spec encode(Qoix.Image.t()) :: {:ok, binary} | {:error, any}
  def encode(%Image{width: w, height: h, pixels: pixels, format: fmt, colorspace: cspace})
      when w > 0 and h > 0 and fmt in [:rgb, :rgba] and cspace in [:srgb, :linear] and
             is_binary(pixels) do
    channels = channels(fmt)
    colorspace = encode_colorspace(cspace)

    chunks =
      pixels
      |> encode_pixels(fmt)
      |> IO.iodata_to_binary()

    # Return the final binary
    data = <<"qoif", w::32, h::32, channels::8, colorspace::8, chunks::bits, @padding::bits>>

    {:ok, data}
  end

  defp channels(:rgb), do: 3
  defp channels(:rgba), do: 4

  defp encode_colorspace(:srgb), do: 0
  defp encode_colorspace(:linear), do: 1

  defp encode_pixels(<<pixels::binary>>, format) when format == :rgb or format == :rgba do
    # Previous pixel is initialized to 0,0,0,255
    prev = <<0, 0, 0, 255>>
    run_length = 0
    lut = @empty_lut
    acc = []

    do_encode(pixels, format, prev, run_length, lut, acc)
  end

  # Here we go with all the possible cases. Order matters due to pattern matching.

  # Maximum representable run_length, push out and start a new one
  defp do_encode(<<pixels::bits>>, format, prev, run_length, lut, acc) when run_length == 62 do
    acc = [acc | <<@run_op::bits, bias_run(run_length)::6>>]

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
    acc = [acc | chunk]

    do_encode(rest, format, pixel, 0, new_lut, acc)
  end

  # For the same reason as above, the pixel is different from the previous.
  # Here we just emit the run length and leave the pixel handling to the next recursion,
  # that will enter in the previous head.
  defp do_encode(<<pixels::bits>>, format, prev, run_length, lut, acc)
       when run_length > 0 do
    acc = [acc | <<@run_op::bits, bias_run(run_length)::6>>]

    do_encode(pixels, format, prev, 0, lut, acc)
  end

  # All pixels consumed, no ongoing run: just output the accumulator
  defp do_encode(<<>>, _format, _prev, 0, _lut, acc) do
    acc
  end

  # All pixels consumed, pending run: output the accumulator and the 6 bit run with its tag
  defp do_encode(<<>>, _format, _prev, run_length, _lut, acc) do
    [acc | <<@run_op::bits, bias_run(run_length)::6>>]
  end

  # Handle a pixel that is not part of a run, return a {chunk, updated_lut} tuple
  defp handle_non_running_pixel(<<r::8, g::8, b::8, a::8>> = pixel, prev, lut) do
    index = index(r, g, b, a)

    case lut do
      %{^index => <<^r::8, ^g::8, ^b::8, ^a::8>>} ->
        {<<@index_op::bits, index::6>>, lut}

      _other ->
        # The value was different from our current pixel
        chunk = diff_luma_color(pixel, prev)
        new_lut = Map.put(lut, index, <<r, g, b, a>>)

        {chunk, new_lut}
    end
  end

  defguardp in_range_2?(val) when val in -2..1
  defguardp in_range_4?(val) when val in -8..7
  defguardp in_range_6?(val) when val in -32..31

  # Check if value can be represented with diff op
  defguardp diff_op?(dr, dg, db) when in_range_2?(dr) and in_range_2?(dg) and in_range_2?(db)

  # Check if value can be represented with luma op
  defguardp luma_op?(dr, dg, db)
            when in_range_6?(dg) and in_range_4?(dr - dg) and in_range_4?(db - dg)

  # Emit a diff, luma, rgb or rgba chunk
  defp diff_luma_color(<<r::8, g::8, b::8, a::8>> = _pixel, <<pr::8, pg::8, pb::8, a::8>> = _prev)
       when diff_op?(r - pr, g - pg, b - pb) do
    <<@diff_op::bits, bias_diff(r - pr)::2, bias_diff(g - pg)::2, bias_diff(b - pb)::2>>
  end

  defp diff_luma_color(<<r::8, g::8, b::8, a::8>> = _pixel, <<pr::8, pg::8, pb::8, a::8>> = _prev)
       when luma_op?(r - pr, g - pg, b - pb) do
    dg = g - pg
    dr_dg = r - pr - dg
    db_dg = b - pb - dg

    <<@luma_op::bits, bias_luma_dg(dg)::6, bias_luma_dr_db(dr_dg)::4, bias_luma_dr_db(db_dg)::4>>
  end

  defp diff_luma_color(<<r::8, g::8, b::8, a::8>>, <<_prgb::24, a::8>> = _prev) do
    # Same alpha, emit RGB
    <<@rgb_op, r::8, g::8, b::8>>
  end

  defp diff_luma_color(<<r::8, g::8, b::8, a::8>>, _prev) do
    # Last resort, full RGBA color
    <<@rgba_op, r::8, g::8, b::8, a::8>>
  end

  @doc """
  Decodes a QOI image, returning an `%Image{}`.

  Returns `{:ok, %Image{}}` on success, `{:error, reason}` on failure.
  """
  @spec decode(binary) :: {:ok, Qoix.Image.t()} | {:error, any}
  def decode(<<encoded::binary>> = _encoded) do
    case encoded do
      <<"qoif", width::32, height::32, channels::8, cspace::8, chunks::binary>> ->
        format = format(channels)
        colorspace = decode_colorspace(cspace)

        pixels =
          chunks
          |> decode_chunks(format)
          |> IO.iodata_to_binary()

        image = %Image{
          width: width,
          height: height,
          pixels: pixels,
          format: format,
          colorspace: colorspace
        }

        {:ok, image}

      _ ->
        {:error, :invalid_qoi}
    end
  end

  defp format(3), do: :rgb
  defp format(4), do: :rgba

  defp decode_colorspace(0), do: :srgb
  defp decode_colorspace(1), do: :linear

  defp decode_chunks(<<chunks::bits>>, format) do
    # Previous pixel is initialized to 0,0,0,255
    prev = <<0, 0, 0, 255>>
    lut = @empty_lut
    acc = []

    do_decode(chunks, format, prev, lut, acc)
  end

  # Let's decode, order matters since 8 bit opcodes have predence over 2 bit opcodes

  # Final padding, we're done, return the accumulator
  defp do_decode(@padding, _format, _prev, _lut, acc) do
    acc
  end

  # RGB: take just alpha from previous pixel
  defp do_decode(<<@rgb_op, r::8, g::8, b::8, rest::bits>>, format, prev, lut, acc) do
    <<_prgb::24, pa::8>> = prev

    pixel = <<r, g, b, pa>>
    acc = [acc | maybe_drop_alpha(pixel, format)]

    do_decode(rest, format, pixel, update_lut(lut, pixel), acc)
  end

  # RGBA: pixel encoded with full information
  defp do_decode(<<@rgba_op, r::8, g::8, b::8, a::8, rest::bits>>, format, _prev, lut, acc) do
    pixel = <<r, g, b, a>>
    acc = [acc | maybe_drop_alpha(pixel, format)]

    do_decode(rest, format, pixel, update_lut(lut, pixel), acc)
  end

  # Index: get the pixel from the LUT
  defp do_decode(<<@index_op, index::6, rest::bits>>, format, _prev, lut, acc) do
    %{^index => pixel} = lut
    acc = [acc | maybe_drop_alpha(pixel, format)]

    do_decode(rest, format, pixel, lut, acc)
  end

  # Run: repeat previous pixel
  defp do_decode(<<@run_op, count::6, rest::bits>>, format, prev, lut, acc) do
    pixels =
      maybe_drop_alpha(prev, format)
      |> :binary.copy(unbias_run(count))

    acc = [acc | pixels]

    do_decode(rest, format, prev, lut, acc)
  end

  # Diff: reconstruct pixel from previous + diff
  defp do_decode(<<@diff_op, dr::2, dg::2, db::2, rest::bits>>, format, prev, lut, acc) do
    <<pr, pg, pb, pa>> = prev
    r = pr + unbias_diff(dr)
    g = pg + unbias_diff(dg)
    b = pb + unbias_diff(db)

    pixel = <<r, g, b, pa>>
    acc = [acc | maybe_drop_alpha(pixel, format)]

    do_decode(rest, format, pixel, update_lut(lut, pixel), acc)
  end

  # Luma: reconstruct pixel from previous + diff
  defp do_decode(<<@luma_op, b_dg::6, dr_dg::4, db_dg::4, rest::bits>>, format, prev, lut, acc) do
    <<pr, pg, pb, pa>> = prev
    dg = unbias_luma_dg(b_dg)
    r = pr + unbias_luma_dr_db(dr_dg) + dg
    g = pg + dg
    b = pb + unbias_luma_dr_db(db_dg) + dg

    pixel = <<r, g, b, pa>>
    acc = [acc | maybe_drop_alpha(pixel, format)]

    do_decode(rest, format, pixel, update_lut(lut, pixel), acc)
  end

  defp maybe_drop_alpha(pixel, :rgba), do: pixel
  defp maybe_drop_alpha(<<r::8, g::8, b::8, _a::8>>, :rgb), do: <<r::8, g::8, b::8>>

  defp index(r, g, b, a) do
    (r * 3 + g * 5 + b * 7 + a * 11)
    |> rem(64)
  end

  defp update_lut(lut, <<r, g, b, a>>) do
    lut_index = index(r, g, b, a)

    Map.put(lut, lut_index, <<r, g, b, a>>)
  end

  defp bias_run(val), do: val - 1
  defp unbias_run(val), do: val + 1

  defp bias_diff(val), do: val + 2
  defp unbias_diff(val), do: val - 2

  defp bias_luma_dg(val), do: val + 32
  defp unbias_luma_dg(val), do: val - 32

  defp bias_luma_dr_db(val), do: val + 8
  defp unbias_luma_dr_db(val), do: val - 8
end
