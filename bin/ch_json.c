/* Copyright © Triad National Security, LLC, and others. */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"

#include CJSON_H

#include "ch_core.h"
#include "ch_json.h"
#include "ch_misc.h"


/** Macros **/


/** Types **/

struct cdi_spec {
   char *kind;
   char *src;       // path to source spec file
   bool requested;
   bool ldconfig_p;
   struct env_var *envs;
   struct bind *binds;
};

struct json_dispatch {
   char *name;
   struct json_dispatch *children;
   void (*f)(cJSON *tree, void *state);
};
#define JDF void (*)(cJSON *, void *) /* to cast callbacks in dispatch tables */


/** Constants **/

// Block size in bytes for reading JSON files.
const size_t READ_SZ = 16384;


/** Function prototypes (private) **/

void cdi_add(struct cdi_spec ***specs, struct cdi_spec *spec_new);
void cdi_free(struct cdi_spec *spec);
void cdi_log(struct cdi_spec *spec);
struct cdi_spec *cdi_read(const char *path);
void visit(struct json_dispatch actions[], cJSON *tree, void *state);
void visit_dispatch(struct json_dispatch action, cJSON *tree, void *state);

// parser callbacks
void cdiPC_kind(cJSON *tree, struct cdi_spec *spec);
void cdiPC_env(cJSON *tree, struct cdi_spec *spec);


/** Global variables **/

/* Callback tables. In the struct, the callback’s second argument is “void *”
   so any state object can be provided. However, we’d prefer the actual
   functions to take the correct pointer type; thus, they need to be cast.
   Alternatives include:

     1. Cast every use of the variable in the callbacks. This seemed verbose
        and error-prone.

     2. Add a local variable of the correct type to each callback. I thought
        such distributed boilerplate seemed worse. */
struct json_dispatch cdiPD_root[] = {
   { "kind", NULL, (JDF)cdiPC_kind },
   { "env",  NULL, (JDF)cdiPC_env },
   { }
};


/** Functions **/

/* Add spec to the given list of CDI specs, which is an out parameter. If
   we’ve seen the spec’s kind before, replace the existing spec with the same
   kind. Otherwise, append the new spec. */
void cdi_add(struct cdi_spec ***specs, struct cdi_spec *spec_new)
{
   if (*specs != NULL)
      for (size_t i = 0; (*specs)[i] != NULL; i++)
         if (!strcmp((*specs)[i]->kind, spec_new->kind)) {
            DEBUG("CDI: spec %s: replacing at %d", spec_new->kind, i);
            free((*specs)[i]);
            *specs[i] = spec_new;
            return;
         }
   // don’t alread have the kind if we got through the loop
   DEBUG("CDI: spec %s: new", spec_new->kind);
   list_append((void **)specs, &spec_new, sizeof(spec_new));
}

/* Free spec. */
void cdi_free(struct cdi_spec *spec)
{
   free(spec->kind);
   free(spec->src);
   for (size_t i = 0; spec->envs[i].name != NULL; i++) {
      free(spec->envs[i].name);
      free(spec->envs[i].value);
   }
   free(spec->envs);
   free(spec);
}

/* Log contents of spec. */
void cdi_log(struct cdi_spec *spec)
{
   size_t ct;

   DEBUG("CDI: spec %s from %s:", spec->kind, spec->src);
   DEBUG("CDI:   devices requested:   %s", bool_to_string(spec->requested));
   DEBUG("CDI:   ldconfig(8) needed:  %s", bool_to_string(spec->ldconfig_p));
   ct = list_count((void *)(spec->envs), sizeof(struct env_var));
   DEBUG("CDI:   environment: %d:", ct);
   for (size_t i = 0; i < ct; i++)
      DEBUG("CDI:     %s=%s", spec->envs[i].name, spec->envs[i].value);
   ct = list_count((void *)(spec->binds), sizeof(struct bind));
   DEBUG("CDI:   bind mounts: %d:", ct);
   for (size_t i = 0; i < ct; i++) {
      DEBUG("CDI:     %s ->  %s", spec->binds[i].src, spec->binds[i].dst);
   }
}

/* Read and parse the CDI spec file at path. Return a pointer to the parsed
   struct, which the caller is responsible for freeing. If something goes
   wrong, exit with error. */
struct cdi_spec *cdi_read(const char *path)
{
   FILE *fp;
   char *text = NULL;
   const char *parse_end;
   cJSON *tree;
   struct cdi_spec *spec = NULL;

   // Read file into string. Allocate incrementally rather than seeking so
   // non-seekable input works.
   Tf (fp = fopen(path, "rb"), "CDI: can't open: %s", path);
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
   T_ (spec->src = strdup(path));
   visit(cdiPD_root, tree, spec);

   // Clean up.
   VERBOSE("CDI: spec read OK: %s: %s", spec->kind, path);
   free(text);
   cJSON_Delete(tree);
   return spec;
}

/* Update container configuration c according to CDI arguments given. Note
   that here we just tidy up the configuration. Actually doing things (e.g.
   bind mounts) happens later. */
void cdi_update(struct container *c, char **devids)
{
   struct cdi_spec *spec;
   struct cdi_spec **specs = NULL;

   // read CDI spec files in configured directories

   // read CDI spec files specifically requested
   for (size_t i = 0; devids[i] != NULL; i++)
      if (devids[i][0] == '.' || devids[i][0] == '/') {
         spec = cdi_read(devids[i]);
         spec->requested = true;
         cdi_add(&specs, spec);
      }

   // debugging: print parsed CDI specs
   for (size_t i = 0; specs[i] != NULL; i++)
      cdi_log(specs[0]);

   // filter device kinds to those requested

   // figure out bind mounts actually needed and set up symlinks

   // set ldconfig bit

   // clean up
   for (size_t i = 0; specs[i] != NULL; i++)
      cdi_free(specs[i]);
   free(specs);
}

void cdiPC_kind(cJSON *tree, struct cdi_spec *spec)
{
   T_ (spec->kind = strdup(tree->valuestring));
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
   ev.name[name_len - 1] = 0;
   T_ (ev.value = malloc(value_len + 1));
   memcpy(ev.value, delim + 1, value_len);
   ev.value[value_len - 1] = 0;
}

/* Visit each node in the parse tree in depth-first order. At each node, if
   there is a matching callback in actions, call it. For arrays, call the
   callback once per array element. */
void visit(struct json_dispatch actions[], cJSON *tree, void *state)
{
   printf("visiting: %s\n", tree->valuestring);
   for (int i = 0; actions[i].name != NULL; i++) {
      cJSON *subtree = cJSON_GetObjectItem(tree, actions[i].name);
      if (cJSON_IsArray(subtree)) {
         cJSON *elem;
         cJSON_ArrayForEach(elem, subtree)
            visit_dispatch(actions[i], elem, state);
      } else {
         visit_dispatch(actions[i], subtree, state);
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
