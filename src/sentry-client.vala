using GLib;

public enum Sentry.ClientFlags
{
	NONE,
	/**
	 * Force all operation to be synchronous when possible.
	 */
	FORCE_SYNCHRONOUS
}

public class Sentry.Client : Object
{
	private extern const string VERSION;
	private extern const string API_VERSION;

	public string? dsn { get; construct; default = null; }

	public ClientFlags client_flags { get; construct; }

	public string?  server_name { get; construct set; default = null; }
	public string?  release     { get; construct set; default = null; }
	public string[] tags        { get; construct set; default = {};   }
	public string?  environment { get; construct set; default = null; }
	public string[] modules     { get; construct set; default = {};   }

	private string  public_key;
	private string? secret_key;
	private string  project_id;

	private Soup.Session sentry_session;

	public Client (string? dsn = null, ClientFlags client_flags = ClientFlags.NONE)
	{
		base (dsn: dsn, client_flags: client_flags);
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
		sentry_session.user_agent = "Sentry-GLib/%s".printf (API_VERSION);
	}

	private Soup.Message generate_message_from_payload (Json.Node payload)
	{
		var msg = new Soup.Message.from_uri ("POST", new Soup.URI ("https://sentry.io/api/%s/store/".printf (project_id)));
		msg.request_headers.replace ("X-Sentry-Auth", "Sentry sentry_version=7, sentry_client=Sentry-GLib/%s, sentry_timestamp=%s, sentry_key=%s, sentry_secret=%s".printf (
		                                              API_VERSION,
		                                              generate_timestamp (),
		                                              public_key,
		                                              secret_key));
		var gen = new Json.Generator ();
		gen.root = payload;
		msg.set_request ("application/json", Soup.MemoryUse.COPY, gen.to_data (null).data);
		return msg;
	}

	/**
	 * Extract the 'id' field safely because we cannot afford any form of error
	 * at this point.
	 */
	private string? extract_id (Json.Node? node)
	{
		if (node == null)
		{
			return null;
		}

		if (node.get_node_type () != Json.NodeType.OBJECT)
		{
			return null;
		}

		var object = node.get_object ();

		if (!object.has_member ("id"))
		{
			return null;
		}

		var id = object.get_member ("id");

		if (id.get_node_type () != Json.NodeType.VALUE || id.get_value_type () != typeof (string))
		{
			return null;
		}

		return id.get_string ();
	}

	private unowned string limit (string str, long len)
	{
		if (str.length > len)
		{
			str.data[str.index_of_nth_char (len)] = '\0';
		}

		return str;
	}

	private string? capture (Json.Node payload)
	{
		var msg = generate_message_from_payload (payload);

		if (dsn == null || dsn == "")
		{
			return null;
		}

		sentry_session.send_message (msg);

		if (msg.status_code == Soup.Status.OK)
		{
			try
			{
				var parser = new Json.Parser ();
				parser.load_from_data ((string) msg.response_body.data);
				return extract_id (parser.get_root ());
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
		var msg = generate_message_from_payload (payload);

		if (dsn == null || dsn == "")
		{
			return null;
		}

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
				return extract_id (parser.get_root ());
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
				.set_member_name ("name").add_string_value ("Sentry-GLib")
				.set_member_name ("version").add_string_value (VERSION)
			.end_object ()
			.get_root ();
	}

	private inline Json.Node generate_stacktrace ()
	{
		var stacktrace = new Json.Builder ();

		stacktrace.begin_object ();

		var ctx = Unwind.Context ();
		var cursor = Unwind.Cursor.local (ctx);

#if LIBDWARF
		int dwarf_code;
		Dwarf.Error? dwarf_error;
		Dwarf.Debug dwarf_debug;
		var self_exe = FileStream.open ("/proc/self/exe", "r");
		assert (null != self_exe);
		dwarf_code = Dwarf.init (self_exe.fileno (), Dwarf.DLC_READ, null, out dwarf_debug, out dwarf_error);
		Dwarf.Cie[] dwarf_cies = {};
		Dwarf.Fde[] dwarf_frames = {};
		if (dwarf_code == Dwarf.DLV_OK)
		{
			dwarf_code = dwarf_debug.get_fde_list (out dwarf_cies, out dwarf_frames, out dwarf_error);

			// check for GNU-style entries instead
			if (dwarf_code == Dwarf.DLV_NO_ENTRY)
			{
				dwarf_code = dwarf_debug.get_fde_list_eh (out dwarf_cies, out dwarf_frames, out dwarf_error);
			}
		}
#endif

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
					.end_object ();

#if LIBDWARF
			if (dwarf_code == Dwarf.DLV_OK)
			{
				Dwarf.Fde dwarf_frame;
				ulong lopc, hipc;
				switch (Dwarf.get_fde_at_pc (dwarf_frames, (ulong) ip, out dwarf_frame, out lopc, out hipc, out dwarf_error))
				{
					case Dwarf.DLV_OK:
						stderr.printf ("Adding dwarf frame..\n");
						break;
					case Dwarf.DLV_ERROR:
						stderr.printf ("Could not add debuginfo for frame.\n");
						break;
				}
			}
#endif

			stacktrace
					.set_member_name ("function").add_string_value ((string) proc_name)
					.set_member_name ("instruction_addr").add_string_value (("%p").printf (ip))
					.set_member_name ("symbol_addr").add_string_value ("%p".printf (proc_info.start_ip))
				.end_object ();
		}
		while (cursor.step () > 0);

#if LIBDWARF
		dwarf_debug.finish ();
#endif

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

	private Json.Node generate_tags ([CCode (array_length = false, array_null_terminated = true)] string[] tags)
	{
		var tagsb = new Json.Builder ();

		tagsb.begin_object ();

		foreach (var tag in this.tags)
		{
			if (tag.index_of_char ('=') > -1) {
				tagsb.set_member_name (limit (tag.substring (0, tag.index_of_char ('=')), 32));
				tagsb.add_string_value (limit (tag.substring (tag.index_of_char ('=') + 1), 200));
			}
		}

		foreach (var tag in tags)
		{
			if (tag.index_of_char ('=') > -1) {
				tagsb.set_member_name (limit (tag.substring (0, tag.index_of_char ('=')), 32));
				tagsb.add_string_value (limit (tag.substring (tag.index_of_char ('=') + 1), 200));
			}
		}

		tagsb.end_object ();

		return tagsb.get_root ();
	}

	private Json.Node generate_modules ()
	{
		var modules = new Json.Builder ();

		modules.begin_object ();

		foreach (var module in this.modules)
		{
			if (module.index_of_char ('=') > -1) {
				modules.set_member_name (module.substring (0, module.index_of_char ('=')));
				modules.add_string_value (module.substring (module.index_of_char ('=') + 1));
			}
		}

		modules.end_object ();

		return modules.get_root ();
	}

	public string? capture_message (string message, [CCode (array_length = false, array_null_terminated = true)] string[] tags = {})
	{
		return capture (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("message").add_string_value (limit (message, 10000))
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("modules").add_value (generate_modules ())
				.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ()
			.get_root ());
	}

	public async string? capture_message_async (string message, [CCode (array_length = false, array_null_terminated = true)] string[]? tags = {})
	{
		return yield capture_async (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("message").add_string_value (limit (message, 10000))
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("modules").add_value (generate_modules ())
				.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ()
			.get_root ());
	}

	public string? capture_error (Error err, [CCode (array_length = false, array_null_terminated = true)] string[] tags = {})
	{
		return capture (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("level").add_string_value ("error")
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("modules").add_value (generate_modules ())
				.set_member_name ("message").add_string_value (limit ("%s (%s, %d)".printf (err.message, err.domain.to_string (), err.code), 10000))
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

	public async string? capture_error_async (Error err, [CCode (array_length = false, array_null_terminated = true)] string[] tags = {})
	{
		return yield capture_async (new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("level").add_string_value ("error")
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("modules").add_value (generate_modules ())
				.set_member_name ("message").add_string_value (limit ("%s (%s, %d)".printf (err.message, err.domain.to_string (), err.code), 10000))
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

	private string level_from_log_level (LogLevelFlags log_level)
	{
		if (LogLevelFlags.LEVEL_ERROR in log_level)
		{
			return "fatal";
		}
		else if (LogLevelFlags.LEVEL_CRITICAL in log_level)
		{
			return "error";
		}
		else if (LogLevelFlags.LEVEL_WARNING in log_level)
		{
			return "warning";
		}
		else if (LogLevelFlags.LEVEL_INFO in log_level)
		{
			return "info";
		}
		else if (LogLevelFlags.LEVEL_DEBUG in log_level)
		{
			return "debug";
		}
		else
		{
			return "info";
		}
	}

	/**
	 * Routine suitable for {@link GLib.Log.set_handler}.
	 *
	 * Note that this instance must be passed for the 'user_data' argument.
	 *
	 * The log is send asynchronously unless the error is marked with {@link GLib.LogLevelFlags.FLAG_FATAL}
	 * or the {@link SentryClient.force_synchronous} property is 'true'.
	 */
	[CCode (instance_pos = -1)]
	public void capture_log (string? log_domain, LogLevelFlags log_flags, string message)
	{

		var payload = new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("level").add_string_value (level_from_log_level (log_flags))
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("modules").add_value (generate_modules ())
				.set_member_name ("message").add_string_value (limit (message, 10000))
				.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ()
			.get_root ();

		if (LogLevelFlags.FLAG_FATAL in log_flags || ClientFlags.FORCE_SYNCHRONOUS in client_flags)
		{
			capture (payload);
		}
		else
		{
			capture_async.begin (payload);
		}
	}

#if GLIB_2_50
	/**
	 * Routine suitable for {@link GLib.Log.set_writer_func}.
	 *
	 * Use this if you would like to dump all the logs to sentry, otherwise
	 * {@link capture_log} is more suitable for a cascading logging model.
	 *
	 * Note that this instance must be passed for the 'user_data' argument.
	 */
	[CCode (instance_pos = -1)]
	public LogWriterOutput capture_structured_log (LogLevelFlags log_level, LogField[] fields)
	{
		var payload = new Json.Builder ()
			.begin_object ()
				.set_member_name ("event_id").add_string_value (generate_event_id ())
				.set_member_name ("timestamp").add_string_value (generate_timestamp ())
				.set_member_name ("sdk").add_value (generate_sdk ())
				.set_member_name ("level").add_string_value (level_from_log_level (log_level))
				.set_member_name ("platform").add_string_value ("c")
				.set_member_name ("tags").add_value (generate_tags (tags))
				.set_member_name ("modules").add_value (generate_modules ());

		foreach (var field in fields)
		{
			switch (field.key)
			{
				case "MESSAGE":
					payload.set_member_name ("message").add_string_value (limit ((string) field.value, 10000));
					break;
				case "MESSAGE_ID":
					break;
			}
		}

		payload
			.set_member_name ("stacktrace").add_value (generate_stacktrace ())
			.end_object ();

		if (LogLevelFlags.FLAG_FATAL in log_level || ClientFlags.FORCE_SYNCHRONOUS in client_flags)
		{
			return capture (payload.get_root ()) == null ? LogWriterOutput.UNHANDLED : LogWriterOutput.HANDLED;
		}
		else
		{
			capture_async.begin (payload.get_root ());
			return LogWriterOutput.HANDLED;
		}
	}
#endif
}
