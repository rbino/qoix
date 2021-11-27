defmodule Qoix do
  @moduledoc """
  Qoix is an Elixir implementation of the [Quite OK Image](https://phoboslab.org/log/2021/11/qoi-fast-lossless-image-compression) format.
  """

  @header_size 12

  @doc """
  Returns true if the binary appears to contain a valid QOI image.
  """
  def qoi?(<<"qoif", _width::size(16), _height::size(16), size::size(32), _::binary>> = binary)
      when byte_size(binary) >= @header_size + size do
    true
  end

  def qoi?(_binary) do
    false
  end
end
