defmodule QoixTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest Qoix

  import Qoix.Generators
  alias Qoix.Image

  @raw_logo_path "test/support/images/elixir-logo.raw"
  @qoi_logo_path "test/support/images/elixir-logo.qoi"
  @logo_width 554
  @logo_height 690

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

    test "correctly encodes the Elixir logo" do
      raw_image =
        @raw_logo_path
        |> File.read!()
        |> then(&Image.from_rgba(@logo_width, @logo_height, &1))

      qoi_logo = File.read!(@qoi_logo_path)

      assert {:ok, encoded} = Qoix.encode(raw_image)
      assert encoded == qoi_logo
    end
  end

  describe "decode/1" do
    property "round trips when using after encode" do
      check all {width, height, rgba_pixels} <- rgba_image_data_generator() do
        image = Image.from_rgba(width, height, rgba_pixels)

        {:ok, encoded} = Qoix.encode(image)

        assert {:ok, ^image} = Qoix.decode(encoded)
      end
    end

    test "correctly decodes the Elixir logo" do
      qoi_logo = File.read!(@qoi_logo_path)

      raw_image =
        @raw_logo_path
        |> File.read!()
        |> then(&Image.from_rgba(@logo_width, @logo_height, &1))

      assert {:ok, decoded} = Qoix.decode(qoi_logo)
      assert decoded == raw_image
    end
  end
end
