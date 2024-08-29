/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <fnmatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

#include "config.h"

#include CJSON_H

#include "core.h"
#include "json.h"
#include "misc.h"


/** Macros **/


/** Types **/

/* Dispatch table row for CDI hook emulation.

   We could alternately put args last, making it a “flexible array member”.
   That would make the field order slightly sub-optimal, but more importantly
   it would make sizeof() return misleading results, which seems like a
   nasty trap waiting for someone. */
#define HOOK_ARG_MAX 3
struct cdi_hook_dispatch {
   size_t arg_ct;             // number of arguments to compare
   char *args[HOOK_ARG_MAX];  // matching arguments
   void (*f)(void *, char **args);    // NULL to ignore quietly
};
#define HDF void (*)(void *, char **args)  // to cast in dispatch tables

struct cdi_spec {
   char *kind;
   char *src_path;         // source spec file path
   dev_t src_dev;          // ... device ID
   ino_t src_ino;          // ... inode number
   struct env_var *envs;
   struct bind *binds;
   char **ldconfigs;       // directories to process with ldconfig(8)
};

struct json_dispatch {
   char *name;
   struct json_dispatch *children;
   void (*f)(cJSON *tree, void *state);
};
#define JDF void (*)(cJSON *, void *)  // to cast callbacks in dispatch tables


/** Constants **/

// Block size in bytes for reading JSON files.
const size_t READ_SZ = 16384;

/** Globals **/

// List of CDI specs we’ve read. Yes it’s a global, but that lets us keep
// struct cdi_spec private to this file, which seemed like the right
// trade-off. It also seemed like “all the specs we know about” wasn’t
// something we needed multiple of.
struct cdi_spec *cdi_specs = NULL;


/** Function prototypes (private) **/

char **array_strings_json_to_c(cJSON *jarry, size_t *ct);
void cdi_append(struct cdi_spec **specs, struct cdi_spec *spec);
void cdi_free(struct cdi_spec *spec);
void cdi_hook_nv_ldcache(struct cdi_spec *spec, char **args);
char *cdi_hook_to_string(const char *hook_name, char **args);
void cdi_log(struct cdi_spec *spec);
struct cdi_spec *cdi_read(const char *path);
struct cdi_spec *cdi_read_maybe(struct cdi_spec *specs, const char *path);
bool cdi_requested(struct cdi_config *cf, struct cdi_spec *spec);
void visit(struct json_dispatch actions[], cJSON *tree, void *state);
void visit_dispatch(struct json_dispatch action, cJSON *tree, void *state);

// parser callbacks
void cdiPC_cdiVersion(cJSON *tree, struct cdi_spec *spec);
void cdiPC_env(cJSON *tree, struct cdi_spec *spec);
void cdiPC_hook(cJSON *tree, struct cdi_spec *spec);
void cdiPC_kind(cJSON *tree, struct cdi_spec *spec);


/** Global variables **/

/* Callback tables. In the struct, the callback’s second argument is “void *”
   so any state object can be provided. However, we’d prefer the actual
   functions to take the correct pointer type; thus, they need to be cast.
   Alternatives include:

     1. Cast every use of the variable in the callbacks. This seemed verbose
        and error-prone.

     2. Add a local variable of the correct type to each callback. I thought
        such distributed boilerplate seemed worse. */
struct json_dispatch cdiPD_containerEdits[] = {
   { "env",            NULL, (JDF)cdiPC_env },
   { "hooks",          NULL, (JDF)cdiPC_hook },
   { }
};
struct json_dispatch cdiPD_root[] = {
   { "cdiVersion",     NULL, (JDF)cdiPC_cdiVersion },
   { "kind",           NULL, (JDF)cdiPC_kind },
   { "containerEdits", cdiPD_containerEdits, },
   { }
};

/* CDI hook dispatch table. */
struct cdi_hook_dispatch cdi_hooks[] = {
   { 2, { "nvidia-ctk-hook",    "update-ldcache" },  (HDF)cdi_hook_nv_ldcache },
   { 3, { "nvidia-ctk", "hook", "update-ldcache" },  (HDF)cdi_hook_nv_ldcache },
   { 2, { "nvidia-ctk-hook",    "chmod" },           NULL },
   { 3, { "nvidia-ctk", "hook", "chmod" },           NULL },
   { 2, { "nvidia-ctk-hook",    "create-symlinks" }, NULL },
   { 3, { "nvidia-ctk", "hook", "create-symlinks" }, NULL },
   { }
};


/** Functions **/


/* Given JSON array of strings jar, which may be of length zero, convert it to
   a freshly allocated NULL-terminated array of C strings (pointers to
   null-terminated chars buffers) and return that. ct is an out parameter

   WARNING: This is a shallow copy, i.e., the actual strings are still owned
   by the JSON array. */
char **array_strings_json_to_c(cJSON *jarry, size_t *ct)
{
   size_t i;
   char **carry;
   cJSON *j;

   Tf (cJSON_IsArray(jarry), "JSON: expected array");
   *ct = cJSON_GetArraySize(jarry);
   T_ (carry = malloc((*ct + 1) * sizeof(char *)));
   carry[*ct] = NULL;

   i = 0;
   cJSON_ArrayForEach(j, jarry) {
      Tf (cJSON_IsString(j), "JSON: expected string");
      carry[i++] = j->valuestring;
   }

   return carry;
}

/* Return true if devid is a device kind (e.g. “nvidia.com/gpu”), false if
   it’s a path. Exit with error if NULL pointer or empty string. */
bool cdi_devid_kind_p(const char *devid)
{
   T_ (devid != NULL && devid[0] != '\0');
   return (devid[0] != '.' && devid[0] != '/');
}

/* Return a list of environment variables to be set for device kind kind, or
   if kind is NULL, all known devices. Both the list and the buffers within
   are newly allocated; the caller must free the list with envs_free(). */
struct env_var *cdi_envs_get(const char *devid)
{
   struct env_var *vars;

   // count variables so we can do just one allocation
   for ()

   // set up the list

   return vars;
}

/* Free spec. */
void cdi_free(struct cdi_spec *spec)
{
   free(spec->kind);
   free(spec->src_path);
   for (size_t i = 0; spec->envs[i].name != NULL; i++) {
      free(spec->envs[i].name);
      free(spec->envs[i].value);
   }
   free(spec->envs);
   for (size_t i = 0; spec->ldconfigs[i] != NULL; i++)
      free(spec->ldconfigs[i]);
   free(spec->ldconfigs);
   free(spec);
}

void cdi_hook_nv_ldcache(struct cdi_spec *spec, char **args)
{
   for (size_t i = 0; args[i] != NULL; i++)
      if (!strcmp("--folder", args[i])) {
         char *dir;
         T_ (args[i+1] != NULL);
         T_ (dir = strdup(args[i+1]));
         // FIXME: YOU ARE HERE: APPEND ONLY IF WE DON'T ALREADY HAVE DIR
         list_append((void **)&spec->ldconfigs, &dir, sizeof(dir));
         i++;
      }
}

/* Return a freshly allocated string describing the given hook, for logging. */
char *cdi_hook_to_string(const char *hook_name, char **args)
{
   char *ret, *args_str;

   args_str = strdup("");
   for (size_t i = 0; args[i] != NULL; i++) {
      char *as_old = args_str;
      T_ (1 <= asprintf(&args_str, "%s %s", as_old, args[i]));
      free(as_old);
   }

   T_ (1 <= asprintf(&ret, "%s:%s", hook_name, args_str));

   free(args_str);
   return ret;
}

/* Read the CDI spec files we need.

   Note: We only read spec files in the search path directories if either
   (a) --devices is specified, requesting all known devices or (b) a device
   kind (rather than a filename) is given to --device (e.g., “nvidia.com/gpu”.
   This protects users from errors in the spec files if they have not
   requested any CDI features. */
void cdi_init(struct cdi_config *cf)
{
   bool req_by_kind = false;

   // Initialize specs list.
   T_ (cdi_specs == NULL);
   cdi_specs = list_new(sizeof(struct cdi_spec), 0);

   // Read CDI spec files specifically requested.
   for (int i = 0; cf->devids[i] != NULL; i++)
      if (cdi_devid_kind_p(cf->devids[i]))
         req_by_kind = true;
      else {
         struct cdi_spec *spec = cdi_read_maybe(cdi_specs, cf->devids[i]);
         if (spec != NULL)
            list_append((void **)&cdi_specs, spec, sizeof(*spec));
         free(spec);
      }

   // Read CDI spec files in configured directories if neccessary.
   if (cf->devs_all_p || req_by_kind)
      for (int i = 0; cf->spec_dirs[i] != NULL; i++) {
         int entry_ct;
         struct dirent **des;
         entry_ct = dir_ls(cf->spec_dirs[i], &des);
         for (int j = 0; j < entry_ct; j++) {
            if (!fnmatch("*.json", des[i]->d_name, 0)) {
               char *path = path_join(cf->spec_dirs[i], des[i]->d_name);
               struct cdi_spec *spec = cdi_read_maybe(cdi_specs, path);
               if (spec != NULL && cdi_requested(cf, spec))
                  list_append((void **)&cdi_specs, spec, sizeof(*spec));
               free(path);
               free(spec);
            }
            free(des[j]);
         }
         free(des);
      }

   // debugging: print parsed CDI specs
   DEBUG("CDI: read %d specs", list_count(cdi_specs, sizeof(cdi_specs[0])));
   for (size_t i = 0; cdi_specs[i].kind != NULL; i++)
      cdi_log(&cdi_specs[0]);

/*
   // update c
   for (size_t i = 0; specs[i] != NULL; i++) {
      // ldconfigs; copy rather than assigning because (1) easier to free
      // and (2) still works if we later grow other sources of ldconfig.
      list_cat((void **)&c->ldconfigs, (void *)specs[i]->ldconfigs,
               sizeof(c->ldconfigs[0]));
   }
*/
}

/* Log contents of spec. */
void cdi_log(struct cdi_spec *spec)
{
   size_t ct;

   DEBUG("CDI: %s from %s (%u,%u %u):", spec->kind, spec->src_path,
         major(spec->src_dev), minor(spec->src_dev), spec->src_ino);
   ct = list_count((void *)(spec->envs), sizeof(struct env_var));
   DEBUG("CDI:   environment: %d:", ct);
   for (size_t i = 0; i < ct; i++)
      DEBUG("CDI:     %s=%s", spec->envs[i].name, spec->envs[i].value);
   ct = list_count((void *)(spec->binds), sizeof(struct bind));
   DEBUG("CDI:   bind mounts: %d:", ct);
   for (size_t i = 0; i < ct; i++)
      DEBUG("CDI:     %s ->  %s", spec->binds[i].src, spec->binds[i].dst);
   ct = list_count((void *)(spec->ldconfigs), sizeof(char *));
   DEBUG("CDI:   ldconfig directories: %d:", ct);
   for (size_t i = 0; i < ct; i++)
      DEBUG("CDI:     %s", spec->ldconfigs[i]);
}

/* Read and parse the CDI spec file at path. Return a pointer to the parsed
   struct, which the caller is responsible for freeing. If something goes
   wrong, exit with error. */
struct cdi_spec *cdi_read(const char *path)
{
   FILE *fp;
   struct stat st;
   char *text = NULL;
   const char *parse_end;
   cJSON *tree;
   struct cdi_spec *spec = NULL;

   // Read file into string. Allocate incrementally rather than seeking so
   // non-seekable input works.
   Tf (fp = fopen(path, "rb"), "CDI: can't open: %s", path);
   Zf (fstat(fileno(fp), &st), "CDI: can't stat: %s", path);
   for (size_t used = 0, avail = READ_SZ; true; avail += READ_SZ) {
      T_ (text = realloc(text, avail));
      size_t read_ct = fread(text + used, 1, READ_SZ, fp);
      used += read_ct;
      if (read_ct < READ_SZ) {
         if (feof(fp)) {            // EOF reached
            text[used] = '\0';  // ensure string ended
            break;
         }
         Tf(0, "CDI: can't read: %s", path);
      }
   }

   // Parse JSON.
   tree = cJSON_ParseWithOpts(text, &parse_end, false);
   Tf(tree != NULL, "CDI: JSON failed at byte %d: %s", parse_end - text, path);

   // Visit parse tree to build our struct.
   T_ (spec = calloc(1, sizeof(struct cdi_spec)));
   T_ (spec->src_path = strdup(path));
   spec->src_dev = st.st_dev;
   spec->src_ino = st.st_ino;
   visit(cdiPD_root, tree, spec);

   // Clean up.
   VERBOSE("CDI: spec read OK: %s: %s", spec->kind, path);
   free(text);
   cJSON_Delete(tree);
   return spec;
}

/* Read and parse the CDI spec file at path, returning a pointer to the
   newly-allocated spec struct, unless (1) we already read the file, in which
   case log that fact and return NULL, or (2) the device kind has already been
   specified, in which case exit with error. If something else goes wrong,
   also exit with error. */
struct cdi_spec *cdi_read_maybe(struct cdi_spec *specs, const char *path)
{
   struct cdi_spec *spec;
   struct stat st;

   // Don’t read file if we already did. It’s relatively easy to give a spec
   // file more than once, e.g. if it’s in the search path and also an
   // argument to --device.
   for (int i = 0; specs[i].kind != NULL; i++) {
      Zf (stat(path, &st), "can’t stat CDI spec: %s", path);
      if (st.st_dev == specs[i].src_dev && st.st_ino == specs[i].src_ino) {
         VERBOSE("CDI: spec already read, skipping: %s", path);
         return NULL;
      }
   }

   spec = cdi_read(path);

   // Error if this device already specified, which because we don’t re-read
   // files means two files specified the same device kind.
   for (int i = 0; specs[i].kind != NULL; i++)
      Te (strcmp(spec->kind, specs[i].kind),
          "CDI: device found in multiple spec files: %s: %s and %s",
          spec->kind, specs[i].src_path, spec->src_path);

   return spec;
}

/* Return true if the given spec was requested by configuration cf, false
   otherwise. */
bool cdi_requested(struct cdi_config *cf, struct cdi_spec *spec)
{
   if (cf->devs_all_p)
      return true;

   for (int i; cf->devids[i] != NULL; i++)
      if (   cdi_devid_kind_p(cf->devids[i])
          && !strcmp(cf->devids[i], spec->kind))
         return true;

   return false;
}

void cdiPC_cdiVersion(cJSON *tree, struct cdi_spec *spec)
{
   DEBUG("CDI: %s: version %s", spec->src_path, tree->valuestring);
}

void cdiPC_env(cJSON *tree, struct cdi_spec *spec)
{
   struct env_var ev;
   size_t name_len, value_len;  // not including null terminator
   char *delim, *arnold;

   T_ (cJSON_IsString(tree));
   T_ (delim = strchr(tree->valuestring, '='));
   T_ (arnold = strchr(tree->valuestring, 0));

   name_len = delim - tree->valuestring;
   value_len = arnold - delim - 1;
   T_ (ev.name = malloc(name_len + 1));
   memcpy(ev.name, tree->valuestring, name_len);
   ev.name[name_len] = 0;
   T_ (ev.value = malloc(value_len + 1));
   memcpy(ev.value, delim + 1, value_len);
   ev.value[value_len] = 0;

   list_append((void **)&spec->envs, &ev, sizeof(ev));
}

void cdiPC_hook(cJSON *tree, struct cdi_spec *spec)
{
   char **args;
   size_t arg_ct;
   char *hook_name;
   char *hook_str;
   bool hook_known;
   //struct cdi_hook_dispatch hook;

   T_ (hook_name = cJSON_GetStringValue(cJSON_GetObjectItem(tree, "hookName")));

   T_ (cJSON_IsArray(cJSON_GetObjectItem(tree, "args")));
   args = array_strings_json_to_c(cJSON_GetObjectItem(tree, "args"), &arg_ct);
   hook_str = cdi_hook_to_string(hook_name, args);

   hook_known = false;
   for (size_t i = 0; cdi_hooks[i].arg_ct != 0; i++) {  // for each table row
      if (arg_ct >= cdi_hooks[i].arg_ct) {   // enough hook args to compare
         for (size_t j = 0; j < cdi_hooks[i].arg_ct; j++)
            if (strcmp(args[j], cdi_hooks[i].args[j]))
                goto continue_outer;
         hook_known = true;  // all words matched
         if (cdi_hooks[i].f == NULL) {
            DEBUG("CDI: ignoring known hook: %s", hook_str);
         } else {
            DEBUG("CDI: emulating known hook: %s", hook_str);
            cdi_hooks[i].f(spec, &args[cdi_hooks[i].arg_ct]);
         }
         break;  // only call one hook function
      }
   continue_outer:
   }

   if (!hook_known)
      WARNING("CDI: ignoring unknown hook: %s", hook_str);

   free(hook_str);
   free(args);
}

void cdiPC_kind(cJSON *tree, struct cdi_spec *spec)
{
   T_ (spec->kind = strdup(tree->valuestring));
}

/* Visit each node in the parse tree in depth-first order. At each node, if
   there is a matching callback in actions, call it. For arrays, call the
   callback once per array element. */
void visit(struct json_dispatch actions[], cJSON *tree, void *state)
{
   for (int i = 0; actions[i].name != NULL; i++) {
      cJSON *subtree = cJSON_GetObjectItem(tree, actions[i].name);
      if (subtree != NULL) {  // child matching action name exists
         if (!cJSON_IsArray(subtree))
            visit_dispatch(actions[i], subtree, state);
         else {
            cJSON *elem;
            cJSON_ArrayForEach(elem, subtree)
               visit_dispatch(actions[i], elem, state);
         }
      }
   }
}

/* Call the appropriate callback for the the root node of tree, if any. Then
   visit its children, if any. */
void visit_dispatch(struct json_dispatch action, cJSON *tree, void *state)
{
   if (action.f != NULL)
      action.f(tree, state);
   if (action.children != NULL)
      visit(action.children, tree, state);
}
