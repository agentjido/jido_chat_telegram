if Code.ensure_loaded?(Dotenvy) do
  cwd = File.cwd!()

  env_from_files =
    Dotenvy.source!([
      Path.absname(".env", cwd),
      Path.absname(".env.test", cwd)
    ])

  # Load dotenv variables into process env for test modules that read System.get_env/1
  # at compile time, while preserving values already explicitly exported in the shell.
  Enum.each(env_from_files, fn {key, value} ->
    if System.get_env(key) in [nil, ""] do
      System.put_env(key, value)
    end
  end)
end

ExUnit.start(exclude: [:live], formatters: [ExUnit.CLIFormatter, Covenant.Formatter])

Code.require_file("contracts/support/fixtures_helper.exs", __DIR__)
