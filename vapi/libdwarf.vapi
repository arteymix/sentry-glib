[CCode (cprefix = "Dwarf_", cheader_filename = "libdwarf/libdwarf.h")]
namespace Dwarf
{
	public delegate void Handler (Error error);

	[CCode (cname = "DW_DLC_READ")]
	public const int DLC_READ;

	[CCode (cname = "DW_DLV_NO_ENTRY")]
	public const int DLV_NO_ENTRY;
	[CCode (cname = "DW_DLV_OK")]
	public const int DLV_OK;
	[CCode (cname = "DW_DLV_ERROR")]
	public const int DLV_ERROR;

	public int init (int fd, int mode, Handler? handler, out Debug dbg, out unowned Error? error = null);

	[SimpleType]
	[CCode (lower_case_cprefix = "dwarf_")]
	public struct Error
	{
		public int errno ();
		public unowned string errmsg ();
	}

	[SimpleType]
	[CCode (lower_case_cprefix = "dwarf_")]
	public struct Debug
	{
		public int finish (out unowned Error? error = null);
		public int get_fde_list (out unowned Cie[] cie_data, out unowned Fde[] fde_data, out unowned Error? error = null);
		public int get_fde_list_eh (out unowned Cie[] cie_data, out unowned Fde[] fde_data, out unowned Error? error = null);
	}

	[SimpleType]
	public struct Cie
	{

	}

	[SimpleType]
	public struct Fde
	{

	}

	public static int get_fde_at_pc ([CCode (array_length = false)] Fde[] fde_data, ulong pc_of_interest, out unowned Fde returned_fde, out ulong lopc, out ulong hipc, out Error? error = null);
}
