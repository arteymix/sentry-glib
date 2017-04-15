#include "sentry-glib.h"

#include <fcntl.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <json-glib/json-glib.h>
#include <libdwarf/libdwarf.h>
#include <libunwind.h>

JsonNode *
sentry_client_generate_stacktrace (SentryClient *self)
{
    JsonBuilder *ret;

    ret = json_builder_new ();

    unw_context_t context;
    unw_cursor_t cursor;

    unw_getcontext (&context);
    unw_init_local (&cursor, &context);

#ifdef LIBDWARF
    gint self_exe;
    Dwarf_Debug dwarf_debug;
    Dwarf_Error dwarf_error;
    Dwarf_Cie *dwarf_cies;
    Dwarf_Signed dwarf_cies_len;
    Dwarf_Fde *dwarf_fdes;
    Dwarf_Signed dwarf_fdes_len;

    self_exe = g_open ("/proc/self/exe", 0, "r");
    dwarf_init (self_exe, DW_DLC_READ, NULL, NULL, &dwarf_debug, &dwarf_error);
    dwarf_get_fde_list_eh (dwarf_debug, &dwarf_cies, &dwarf_cies_len, &dwarf_fdes, &dwarf_fdes_len, &dwarf_error);
#endif

    json_builder_begin_object (ret);

    json_builder_set_member_name (ret, "frames");
    json_builder_begin_array (ret);

    while (unw_step (&cursor))
    {
        unw_word_t ip, sp, eh;
        unw_get_reg (&cursor, UNW_REG_IP, &ip);
        unw_get_reg (&cursor, UNW_REG_SP, &sp);
        unw_get_reg (&cursor, UNW_REG_EH, &eh);

        if (ip == 0)
        {
            break;
        }

        json_builder_begin_object (ret);

#ifdef LIBDWARF
        Dwarf_Fde dwarf_fde;
        Dwarf_Addr lopc, hipc;
        switch (dwarf_get_fde_at_pc (dwarf_fdes, (Dwarf_Addr) ip, &dwarf_fde, &lopc, &hipc, &dwarf_error))
        {
            case DW_DLV_OK:
                json_builder_set_member_name (ret, "in_app");
                json_builder_add_boolean_value (ret, TRUE);
                break;
            case DW_DLV_NO_ENTRY:
                json_builder_set_member_name (ret, "in_app");
                json_builder_add_boolean_value (ret, FALSE);
                break;
        }
#endif

        json_builder_set_member_name (ret, "vars");
        json_builder_begin_object (ret);
        json_builder_set_member_name (ret, "ip");
        json_builder_add_string_value (ret, g_strdup_printf ("%p", (void*) ip));
        json_builder_set_member_name (ret, "sp");
        json_builder_add_string_value (ret, g_strdup_printf ("%p", (void*) sp));
        json_builder_set_member_name (ret, "eh");
        json_builder_add_string_value (ret, g_strdup_printf ("%p", (void*) eh));
        json_builder_end_object (ret);

        gchar proc_name[128];
        unw_proc_info_t proc_info;
        unw_get_proc_name (&cursor, proc_name, 128, NULL);
        unw_get_proc_info (&cursor, &proc_info);

        json_builder_set_member_name (ret, "function");
        json_builder_add_string_value (ret, proc_name);
        json_builder_set_member_name (ret, "instruction_addr");
        json_builder_add_string_value (ret, g_strdup_printf ("%p", (void*) ip));
        json_builder_set_member_name (ret, "symbol_addr");
        json_builder_add_string_value (ret, g_strdup_printf ("%p", (void*) proc_info.start_ip));

        json_builder_end_object (ret);
    }

    json_builder_end_array (ret);

    json_builder_end_object (ret);

#if LIBDWARF
    dwarf_finish (dwarf_debug, &dwarf_error);
    g_close (self_exe, NULL);
#endif

    return json_builder_get_root (ret);
}
