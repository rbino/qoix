defmodule Qoix.Image do
  @moduledoc """
  A struct representing a raw RGBA image.
  """

  @enforce_keys [:width, :height, :pixels]
  defstruct [:width, :height, :pixels]

  alias __MODULE__

  @doc """
  Creates a new `Qoix.Image` which can be passed to the `Qoix.encode/1` function.

  `pixels` must be a binary of RGB values.
  """
  def from_rgb(width, height, pixels)
      when is_integer(width) and is_integer(height) and is_binary(pixels) and width > 0 and
             height > 0 do
    %Image{
      width: width,
      height: height,
      pixels: to_rgba(pixels)
    }
  end

  @doc """
  Creates a new `Qoix.Image` which can be passed to the `Qoix.encode/1` function.

  `pixels` must be a binary of RGBA values.
  """
  def from_rgba(width, height, pixels)
      when is_integer(width) and is_integer(height) and is_binary(pixels) and width > 0 and
             height > 0 do
    %Image{
      width: width,
      height: height,
      pixels: pixels
    }
  end

  defp to_rgba(pixels) do
    pixels
    |> to_rgba([])
    |> IO.iodata_to_binary()
  end

  defp to_rgba(<<r::size(8), g::size(8), b::size(8), rest::binary>>, acc) do
    to_rgba(rest, [acc | <<r, g, b, 255>>])
  end

  defp to_rgba(<<>>, acc) do
    acc
  end
end
