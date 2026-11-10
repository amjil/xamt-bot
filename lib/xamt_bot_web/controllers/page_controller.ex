defmodule XamtBotWeb.PageController do
  use XamtBotWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
