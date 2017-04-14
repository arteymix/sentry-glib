public errordomain FooError
{
	FAILED
}

public int main (string[] args)
{
	Test.init (ref args);

	Test.add_func ("/null-dsn", () => {
		var sentry = new Sentry.Client (null);
		assert (null == sentry.capture_message ("test"));
	});

	Test.add_func ("/empty-dsn", () => {
		var sentry = new Sentry.Client ("");
		assert (null == sentry.capture_message ("test"));
	});

	Test.add_func ("/capture-message", () => {
		var sentry_dsn = Environment.get_variable ("SENTRY_DSN");

		if (sentry_dsn == null || sentry_dsn == "")
		{
			Test.skip ("The 'SENTRY_DSN' environment variable is not set or empty.");
			return;
		}

		var sentry = new Sentry.Client (sentry_dsn);

		assert (sentry.capture_message ("bar") != null);
	});

	Test.add_func ("/capture-error", () => {
		var sentry_dsn = Environment.get_variable ("SENTRY_DSN");

		if (sentry_dsn == null || sentry_dsn == "")
		{
			Test.skip ("The 'SENTRY_DSN' environment variable is not set or empty.");
			return;
		}

		var sentry = new Sentry.Client (sentry_dsn);

		sentry.capture_error (new FooError.FAILED ("bar"));
	});

	Test.add_func ("/capture-log", () => {
		var sentry_dsn = Environment.get_variable ("SENTRY_DSN");

		if (sentry_dsn == null || sentry_dsn == "")
		{
			Test.skip ("The 'SENTRY_DSN' environment variable is not set or empty.");
			return;
		}

		if (Test.subprocess ())
		{
			var sentry = new Sentry.Client (sentry_dsn, Sentry.ClientFlags.FORCE_SYNCHRONOUS);
			Log.set_handler (null, LogLevelFlags.LEVEL_MESSAGE, sentry.capture_log);
			message ("bar");
			return;
		}

		Test.trap_subprocess (null, 0, 0);

		Test.trap_assert_passed ();
		Test.trap_assert_stderr ("");
	});

	Test.add_func ("/capture-fatal-log", () => {
		var sentry_dsn = Environment.get_variable ("SENTRY_DSN");

		if (sentry_dsn == null || sentry_dsn == "")
		{
			Test.skip ("The 'SENTRY_DSN' environment variable is not set or empty.");
			return;
		}

		if (Test.subprocess ())
		{
			var sentry = new Sentry.Client (sentry_dsn, Sentry.ClientFlags.FORCE_SYNCHRONOUS);
			Log.set_handler (null, LogLevelFlags.LEVEL_ERROR | LogLevelFlags.FLAG_FATAL, sentry.capture_log);
			error ("bar");
		}

		Test.trap_subprocess (null, 10000, TestSubprocessFlags.STDERR);

		Test.trap_assert_failed ();
		Test.trap_assert_stderr ("");
	});

#if GLIB_2_50
	Test.add_func ("/structured-logging", () => {
		var sentry_dsn = Environment.get_variable ("SENTRY_DSN");

		if (sentry_dsn == null || sentry_dsn == "")
		{
			Test.skip ("The 'SENTRY_DSN' environment variable is not set or empty.");
			return;
		}

		if (Test.subprocess ())
		{
			var sentry = new Sentry.Client (sentry_dsn, Sentry.ClientFlags.FORCE_SYNCHRONOUS);
			Log.set_writer_func (sentry.capture_structured_log);
			message ("bar");
			return;
		}

		Test.trap_subprocess (null, 0, 0);

		Test.trap_assert_passed ();
		Test.trap_assert_stderr ("");
	});
#endif

	return Test.run ();
}
