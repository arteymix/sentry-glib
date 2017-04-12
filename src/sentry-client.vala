using GLib;

public class Sentry.Client : Object
{
	public string? dsn { get; construct; default = null; }

	public string?  server_name { get; construct set; default = null; }
	public string?  release     { get; construct set; default = null; }
	public string[] tags        { get; construct set; default = {};   }
	public string?  environment { get; construct set; default = null; }
	public string[] modules     { get; construct set; default = {};   }

	private string  public_key;
	private string? secret_key;
	private string  project_id;

	private Soup.Session sentry_session;

	public Client (string? dsn = null)
	{
		base (dsn: dsn);
	}

	construct
	{
		if (dsn != null && dsn != "")
		{
			var uri = new Soup.URI (dsn);
			public_key = uri.user;
			secret_key = uri.password;
			project_id = uri.path[1:uri.path.length];
		}
		sentry_session = new Soup.Session ();
		sentry_session.user_agent = "Sentry-GLib/1.0";
	}

	private Soup.Message generate_message_from_payload (Json.Node payload)
	{
		var msg = new Soup.Message.from_uri ("POST", new Soup.URI ("https://sentry.io/api/%s/store/".printf (project_id)));
		msg.request_headers.replace ("X-Sentry-Auth", "Sentry sentry_version=7, sentry_client=Sentry-GLib/1.0, sentry_timestamp=%s, sentry_key=%s, sentry_secret=%s".printf (
		                                              generate_timestamp (),
		                                              public_key,
		                                              secret_key));
		var gen = new Json.Generator ();
		gen.root = payload;
		msg.set_request ("application/json", Soup.MemoryUse.COPY, gen.to_data (null).data);
		return msg;
	}

	private string? capture (Json.Node payload)
	{
		if (dsn == null || dsn == "")
		{
			return null;
		}

		var msg = generate_message_from_payload (payload);
		sentry_session.send_message (msg);

		if (msg.status_code == Soup.Status.OK)
		{
			try
			{
				var parser = new Json.Parser ();
				parser.load_from_data ((string) msg.response_body.data);
				return parser.get_root ().get_object ().get_string_member ("id");
			}
			catch (Error err)
			{
				stderr.printf ("%s (%s, %d)\n", err.message, err.domain.to_string (), err.code);
				return null;
			}
		}
		else
		{
			stderr.printf ("%s\n", msg.response_headers.get_one ("X-Sentry-Error") ?? "Unknown error.");
			return null;
		}
	}

	private async string? capture_async (Json.Node payload)
	{
		if (dsn == null || dsn == "")
		{
			return null;
		}

		var msg = generate_message_from_payload (payload);

		sentry_session.queue_message (msg, () => {
			capture_async.callback ();
		});
		yield;

		if (msg.status_code == Soup.Status.OK)
		{
			try
			{
				var parser = new Json.Parser ();
				parser.load_from_data ((string) msg.response_body.data);
				return parser.get_root ().get_object ().get_string_member ("id");
			}
			catch (Error err)
			{
				stderr.printf ("%s (%s, %d)\n", err.message, err.domain.to_string (), err.code);
				return null;
			}
		}
		else
		{
			stderr.printf ("%s\n", msg.response_headers.get_one ("X-Sentry-Error") ?? "Unknown error.");
			return null;
		}
	}

	private string generate_event_id ()
	{
		uint8 event_id[16];
		char event_id_str[37];
		UUID.generate_random (event_id);
		UUID.unparse (event_id, event_id_str);
		return ((string) event_id_str).replace ("-", "");
	}

	private string generate_timestamp ()
	{
		return new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%S");
	}

	private Json.Node generate_sdk ()
	{
		return new Json.Builder ()
			.begin_object ()
				.set_member_name ("name").add_string_value ("sentry-glib")
				.set_member_name ("version").add_string_value ("1.0.0")
			.end_object ()
			.get_root ();
	}

	private inline Json.Node generate_stacktrace ()
	{
		var stacktrace = new Json.Builder ();

		stacktrace.begin_object ();

		var ctx = Unwind.Context ();
		var cursor = Unwind.Cursor.local (ctx);

		stacktrace.set_member_name ("frames");
		stacktrace.begin_array ();

		do
		{
			uint8 proc_name[128];
			Unwind.ProcInfo proc_info;
			cursor.get_proc_name (proc_name);
			cursor.get_proc_info (out proc_info);
			void* ip, sp, eh;
			cursor.get_reg (Unwind.Reg.IP, out ip);
			cursor.get_reg (Unwind.Reg.SP, out sp);
			cursor.get_reg (Unwind.Reg.EH, out eh);
			if (proc_name[0] == '\0') {
				continue;
			}
			stacktrace
				.begin_object ()
					.set_member_name ("vars")
					.begin_object ()
						.set_member_name ("sp").add_string_value ("%p".printf (sp))
						.set_member_name ("eh").add_string_value ("%p".printf (eh))
					.end_object ()
					.set_member_name ("function").add_string_value ((string) proc_name)
					.set_member_name ("instruction_addr").add_string_value (("%p").printf (ip))
					.set_member_name ("symbol_addr").add_string_value ("%p".printf (proc_info.start_ip))
				.end_object ();
		}
		while (cursor.step () > 0);

		stacktrace.end_array ();
		stacktrace.end_object ();

		return stacktrace.get_root ();
	}

	private inline Json.Node generate_exception (Error err)
	{
		return new Json.Builder ()
			.begin_object ()
				.set_member_name ("type").add_string_value (err.domain.to_string ())
				.set_member_name ("value").add_string_value (err.message)
				.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ()
			.get_root ();
	}

	private Json.Node generate_tags (string[] tags)
	{
		var tagsb = new Json.Builder ();

		tagsb.begin_object ();

		foreach (var tag in this.tags)
		{
			if (tag.index_of_char ('=') > -1) {
				tagsb.set_member_name (tag.substring (0, tag.index_of_char ('=')));
				tagsb.add_string_value (tag.substring (tag.index_of_char ('=') + 1));
			}
		}

		foreach (var tag in tags)
		{
			if (tag.index_of_char ('=') > -1) {
				tagsb.set_member_name (tag.substring (0, tag.index_of_char ('=')));
				tagsb.add_string_value (tag.substring (tag.index_of_char ('=') + 1));
			}
		}

		tagsb.end_object ();

		return tagsb.get_root ();
	}

	public string? capture_message (string message, string[] tags = {})
	{
		return capture (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("message").add_string_value (message)
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ()
			.get_root ());
	}

	public async string? capture_message_async (string message, string[] tags = {})
	{
		return yield capture_async (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("message").add_string_value (message)
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ()
			.get_root ());
	}

	public string? capture_error (Error err, string[] tags = {})
	{
		return capture (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("level").add_string_value ("error")
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("message").add_string_value ("%s (%s, %d)".printf (err.message, err.domain.to_string (), err.code))
				.set_member_name ("exception")
				.begin_object ()
					.set_member_name ("values")
					.begin_array ()
						.add_value (generate_exception (err))
					.end_array ()
				.end_object ()
			.end_object ()
			.get_root ());
	}

	public async string? capture_error_async (Error err, string[] tags = {})
	{
		return yield capture_async (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("level").add_string_value ("error")
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("message").add_string_value ("%s (%s, %d)".printf (err.message, err.domain.to_string (), err.code))
				.set_member_name ("exception")
				.begin_object ()
					.set_member_name ("values")
					.begin_array ()
						.add_value (generate_exception (err))
					.end_array ()
				.end_object ()
			.end_object ()
			.get_root ());
	}

	/**
	 * Routine suitable for {@link GLib.Log.set_handler}.
	 *
	 * Note that this instance must be passed for the 'user_data' argument.
	 */
	[CCode (instance_pos = -1)]
	public void capture_log (string? log_domain, LogLevelFlags log_flags, string message)
	{
		string level;
		if (LogLevelFlags.LEVEL_ERROR in log_flags)
		{
			level = "fatal";
		}
		else if (LogLevelFlags.LEVEL_CRITICAL in log_flags)
		{
			level = "error";
		}
		else if (LogLevelFlags.LEVEL_WARNING in log_flags)
		{
			level = "warning";
		}
		else if (LogLevelFlags.LEVEL_INFO in log_flags)
		{
			level = "info";
		}
		else if (LogLevelFlags.LEVEL_DEBUG in log_flags)
		{
			level = "debug";
		}
		else
		{
			level = "info";
		}

		var payload = new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("level").add_string_value (level)
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("message").add_string_value (message)
				.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ()
			.get_root ();

		if (LogLevelFlags.FLAG_FATAL in log_flags)
		{
			capture (payload);
		}
		else
		{
			capture_async.begin (payload);
		}
	}
}
