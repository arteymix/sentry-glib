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

		sentry.capture_message ("bar");
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

	return Test.run ();
}
