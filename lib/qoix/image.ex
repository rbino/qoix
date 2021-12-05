defmodule Qoix.Image do
  @moduledoc """
  A struct representing a raw RGBA image.
  """

  @enforce_keys [:width, :height, :pixels, :format]
  defstruct [:width, :height, :pixels, :format]

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
      pixels: pixels,
      format: :rgb
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
      pixels: pixels,
      format: :rgba
    }
  end
end
