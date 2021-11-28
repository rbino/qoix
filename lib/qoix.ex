defmodule Qoix do
  @moduledoc """
  Qoix is an Elixir implementation of the [Quite OK Image](https://phoboslab.org/log/2021/11/qoi-fast-lossless-image-compression) format.
  """


  @doc """
  Returns true if the binary appears to contain a valid QOI image.
  """
  def qoi?(<<"qoif", _width::32, _height::32, channels::8, _colorspace::8, _rest::binary>>)
      when channels == 3 or channels == 4 do
    true
  end

  def qoi?(_binary) do
    false
  end
end
