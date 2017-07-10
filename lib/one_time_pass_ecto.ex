defmodule OneTimePassEcto do
  @moduledoc """
  Module to handle one-time passwords, usually for use in two factor
  authentication.

  ## One-time password options

  There are the following options for the one-time passwords:

    * HMAC-based one-time passwords
      * token_length - the length of the one-time password
        * the default is 6
      * last - the count when the one-time password was last used
        * this count needs to be stored server-side
      * window - the number of future attempts allowed
        * the default is 3
    * Time-based one-time passwords
      * token_length - the length of the one-time password
        * the default is 6
      * interval_length - the length of each timed interval
        * the default is 30 (seconds)
      * window - the number of attempts, before and after the current one, allowed
        * the default is 1 (1 interval before and 1 interval after)

  See the documentation for the OneTimePassEcto.Base module for more details
  about generating and verifying one-time passwords.
  """

  import Ecto.{Changeset, Query}
  alias OneTimePassEcto.Base

  @doc """
  Check the one-time password, and return {:ok, user} if the one-time
  password is correct or {:error, message} if there is an error.

  After this function has been called, you need to either add the user
  to the session, by running `put_session(conn, :user_id, id)`, or send
  an API token to the user.

  See the `One-time password options` in this module's documentation
  for available options to be used as the second argument to this
  function.
  """
  def verify(params, repo, user_schema, opts \\ [])
  def verify(%{"id" => id, "hotp" => hotp}, repo, user_schema, opts) do
    {:ok, result} = repo.transaction(fn ->
      get_user_with_lock(repo, user_schema, id)
      |> check_hotp(hotp, opts)
      |> update_otp(repo)
    end)
    result
  end
  def verify(%{"id" => id, "totp" => totp}, repo, user_schema, opts) do
    repo.get(user_schema, id)
    |> check_totp(totp, opts)
    |> update_otp(repo)
  end

  defp check_hotp(user, hotp, opts) do
    {user, Base.check_hotp(hotp, user.otp_secret, [last: user.otp_last] ++ opts)}
  end

  defp check_totp(user, totp, opts) do
    {user, Base.check_totp(totp, user.otp_secret, opts)}
  end

  defp get_user_with_lock(repo, user_schema, id) do
    from(u in user_schema, where: u.id == ^id, lock: "FOR UPDATE")
    |> repo.one!
  end

  defp update_otp({_, false}, _), do: {:error, "invalid one-time password"}
  defp update_otp({%{otp_last: otp_last} = user, last}, repo) when last > otp_last do
    change(user, %{otp_last: last}) |> repo.update
  end
  defp update_otp(_, _), do: {:error, "invalid user-identifier"}
end
