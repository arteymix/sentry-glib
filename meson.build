project('Sentry-GLib', 'c', 'vala',
        version: '0.1.0-dev')

api_version = '0.1'

add_project_arguments('--vapidir=' + meson.current_source_dir() + '/vapi',
                      language: 'vala')

glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
libsoup_dep = dependency('libsoup-2.4')
json_glib_dep = dependency('json-glib-1.0')
uuid_dep = dependency('uuid')
libunwind_dep = dependency('libunwind-generic')
libdwarf_lib = meson.get_compiler('c').find_library('dwarf', required: false)
libdwarf_vapi = meson.get_compiler('vala').find_library('libdwarf', dirs: join_paths(meson.current_source_dir(), 'vapi'))
libdwarf_dep = declare_dependency(dependencies: [libdwarf_lib, libdwarf_vapi])
libelf_dep = dependency('libelf', required: false)

if glib_dep.version().version_compare('>=2.50')
    add_project_arguments('--define=GLIB_2_50', language: 'vala')
endif

if libdwarf_lib.found() and libelf_dep.found()
    add_project_arguments('--define=LIBDWARF', language: 'vala')
endif

subdir('src')
subdir('tests')
