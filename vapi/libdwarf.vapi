[CCode (cprefix = "Dwarf_", cheader_filename = "libdwarf/libdwarf.h")]
namespace Dwarf
{
	public delegate void Handler (Error error);

	[CCode (cname = "DW_DLC_READ")]
	public const int DLC_READ;
	[CCode (cname = "DW_DLV_OK")]
	public const int DLV_OK;

	public int init (int fd, int mode, Handler? handler, out Debug dbg, out Error? error = null);

	[SimpleType]
	public struct Error
	{

	}

	[SimpleType]
	[CCode (lower_case_cprefix = "dwarf_")]
	public struct Debug
	{
		public int finish (out Error? error = null);
	}
}
