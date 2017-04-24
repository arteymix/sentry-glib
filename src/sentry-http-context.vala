public class Sentry.HttpContext : Sentry.Context
{
	public string     url          { get; construct; }
	public string     method       { get; construct; default = "GET"; }
	public string?    data         { get; construct; default = null;  }
	public string?    query_string { get; construct; default = null;  }
	public string?    cookies      { get; construct; default = null;  }

	public HttpContext (string  url,
	                    string  method       = "GET",
	                    string? data         = null,
	                    string? query_string = null,
	                    string? cookies      = null)
	{
		Object (url: url, method: method, data: data, query_string: query_string, cookies: cookies);
	}

	public override string get_key ()
	{
		return "request";
	}
}
