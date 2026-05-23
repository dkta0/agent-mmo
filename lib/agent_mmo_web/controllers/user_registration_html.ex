defmodule AgentMmoWeb.UserRegistrationHTML do
  use AgentMmoWeb, :html

  embed_templates "user_registration_html/*"

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string_safe(value))
    end)
  end

  defp to_string_safe(value) when is_list(value), do: inspect(value)
  defp to_string_safe(value), do: to_string(value)
end
