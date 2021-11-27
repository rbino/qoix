defmodule Qoix.Generators do
  use ExUnitProperties

  def rgb_image_data_generator do
    gen all width <- positive_integer(),
            height <- positive_integer() do
      pixels =
        rgb_pixel_generator()
        |> Enum.take(width * height)
        |> IO.iodata_to_binary()

      {width, height, pixels}
    end
  end

  def rgb_pixel_generator do
    gen all r <- byte_generator(),
            g <- byte_generator(),
            b <- byte_generator() do
      <<r, g, b>>
    end
  end

  def rgba_image_data_generator do
    gen all width <- positive_integer(),
            height <- positive_integer() do
      pixels =
        rgba_pixel_generator()
        |> Enum.take(width * height)
        |> IO.iodata_to_binary()

      {width, height, pixels}
    end
  end

  def rgba_pixel_generator do
    gen all r <- byte_generator(),
            g <- byte_generator(),
            b <- byte_generator(),
            a <- byte_generator() do
      <<r, g, b, a>>
    end
  end

  def byte_generator do
    map(positive_integer(), &rem(&1, 256))
  end
end
