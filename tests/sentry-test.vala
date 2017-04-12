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

	return Test.run ();
}
