defmodule Qoix.Image do
  @moduledoc """
  A struct representing a raw RGBA image.
  """

  @enforce_keys [:width, :height, :pixels, :format, :colorspace]
  defstruct [:width, :height, :pixels, :format, :colorspace]

  alias __MODULE__

  @doc """
  Creates a new `Qoix.Image` which can be passed to the `Qoix.encode/1` function.

  `pixels` must be a binary of RGB values.

  It's possible to pass an optional `colorspace`, which must be one of `:srgb` (sRGB with linear
  alpha) or `:linear` (all channels linear). If nothing is passed, the default is `:srgb`
  """
  def from_rgb(width, height, pixels, colorspace \\ :srgb)
      when is_integer(width) and is_integer(height) and is_binary(pixels) and width > 0 and
             height > 0 and colorspace in [:srgb, :linear] do
    %Image{
      width: width,
      height: height,
      pixels: pixels,
      format: :rgb,
      colorspace: colorspace
    }
  end

  @doc """
  Creates a new `Qoix.Image` which can be passed to the `Qoix.encode/1` function.

  `pixels` must be a binary of RGBA values.

  It's possible to pass an optional `colorspace`, which must be one of `:srgb` (sRGB with linear
  alpha) or `:linear` (all channels linear). If nothing is passed, the default is `:srgb`
  """
  def from_rgba(width, height, pixels, colorspace \\ :srgb)
      when is_integer(width) and is_integer(height) and is_binary(pixels) and width > 0 and
             height > 0 and colorspace in [:srgb, :linear] do
    %Image{
      width: width,
      height: height,
      pixels: pixels,
      format: :rgba,
      colorspace: colorspace
    }
  end
end
