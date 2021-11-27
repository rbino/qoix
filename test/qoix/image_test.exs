defmodule Qoix.ImageTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest Qoix

  import Qoix.Generators
  alias Qoix.Image

  describe "from_rgb/3" do
    property "RGB pixels are converted to RGBA" do
      check all {width, height, rgb_pixels} <- rgb_image_data_generator() do
        assert %Image{width: ^width, height: ^height, pixels: rgba_pixels} =
                 Image.from_rgb(width, height, rgb_pixels)

        for idx <- 0..(width * height - 1) do
          <<r, g, b>> = :binary.part(rgb_pixels, idx * 3, 3)
          assert <<^r, ^g, ^b, 255>> = :binary.part(rgba_pixels, idx * 4, 4)
        end
      end
    end
  end

  describe "from_rgba/3" do
    property "simply wraps the passed arguments" do
      check all {width, height, pixels} <- rgb_image_data_generator() do
        assert %Image{width: ^width, height: ^height, pixels: ^pixels} =
                 Image.from_rgba(width, height, pixels)
      end
    end
  end
end
