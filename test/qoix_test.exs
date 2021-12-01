defmodule QoixTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest Qoix

  import Qoix.Generators
  alias Qoix.Image

  describe "encode/1" do
    property "the resulting image has the correct header dimensions and padding" do
      check all {width, height, rgba_pixels} <- rgba_image_data_generator() do
        assert {:ok, encoded} =
                 Image.from_rgba(width, height, rgba_pixels)
                 |> Qoix.encode()

        assert <<"qoif", ^width::32, ^height::32, channels::8, _colorspace::8, data::binary>> =
                 encoded

        assert channels == 4
        padding_start = byte_size(data) - 4
        assert :binary.part(data, padding_start, 4) == <<0, 0, 0, 0>>
        assert byte_size(data) <= rgba_pixels

        assert Qoix.qoi?(encoded) == true
      end
    end
  end
end
