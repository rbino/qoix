defmodule Qoix.ImageTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest Qoix

  import Qoix.Generators
  alias Qoix.Image

  describe "from_rgb/3" do
    property "simply wraps the passed arguments, adding the correct format" do
      check all {width, height, rgb_pixels} <- rgb_image_data_generator() do
        assert %Image{width: ^width, height: ^height, pixels: ^rgb_pixels, format: :rgb} =
                 Image.from_rgb(width, height, rgb_pixels)
      end
    end
  end

  describe "from_rgba/3" do
    property "simply wraps the passed arguments, adding the correct format" do
      check all {width, height, pixels} <- rgb_image_data_generator() do
        assert %Image{width: ^width, height: ^height, pixels: ^pixels, format: :rgba} =
                 Image.from_rgba(width, height, pixels)
      end
    end
  end
end
