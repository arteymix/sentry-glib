public class Sentry.UserContext : Sentry.Context
{
	public string  id         { get; construct; }
	public string? email      { get; construct; default = null; }
	public string? ip_address { get; construct; default = null; }
	public string? username   { get; construct; default = null; }

	public UserContext (string id, string? email = null, string? ip_address = null, string? username = null)
	{
		Object (id: id, email: email, ip_address: ip_address, username: username);
	}

	public override string get_key ()
	{
		return "user";
	}
}
