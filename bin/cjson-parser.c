
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cjson/cJSON.h>


struct json_dispatch {
    char *name;
    struct json_dispatch *children;
    void (*f)(cJSON *);
};


void readJSONFile(const char *filename);
void iterJSONFile(cJSON *json);
void visit(struct json_dispatch actions[], cJSON *json);
void dispatch(struct json_dispatch action, cJSON *json);
void oci_ociVersion(cJSON *json);
void oci_env(cJSON *json);
void oci_cwd(cJSON *json);
void oci_path(cJSON *json);
void oci_readonly(cJSON *json);


struct json_dispatch oci_process[] = {
    { "env",            NULL, oci_env },
    { "cwd",            NULL, oci_cwd },
    { }
};
struct json_dispatch oci_root[] = {
    { "path",           NULL, oci_path },
    { "readonly",       NULL, oci_readonly },
    { }
};
struct json_dispatch oci_top[] = {
    { "ociVersion",     NULL, oci_ociVersion },
    { "process",        oci_process },
    { "root",           oci_root },
    { }
};


int main() {
    const char *filename = "config.json";
    readJSONFile(filename);
    return 0;
}


void readJSONFile(const char *filename) {

    FILE *file = fopen(filename, "rb");
    char *buffer = NULL;
    size_t length, file_len;
    
    if (file == NULL) {
        fprintf(stderr, "Error: could not open file %s\n", filename);
        return;
    }

    // Get the file length
    fseek(file, 0, SEEK_END);
    length = ftell(file);
    fseek(file, 0, SEEK_SET);
    // Allocate content buffer
    buffer = malloc(length);
    file_len = fread(buffer, 1, length, file);
    printf("Read %lu bytes of %lu\n", file_len, length);

    fclose(file);

    // Parse the JSON data
    cJSON *json = cJSON_Parse(buffer);
    // Check if parsing was successful
    if (json == NULL) {
        const char *error_ptr = cJSON_GetErrorPtr();
        if (error_ptr != NULL) {
            fprintf(stderr, "Error before: %s\n", error_ptr);
        }
        goto end;
    }

    // Print the JSON data
    char *json_tree = cJSON_Print(json);
    if (json_tree == NULL)
    {
        fprintf(stderr, "Failed to print JSON tree.\n");
    }
    //printf("%s\n", json_tree);

    // Process the JSON data
    visit(oci_top, json);

    // Clean up
end:
    cJSON_Delete(json);
    free(buffer);
}

void dispatch(struct json_dispatch action, cJSON *json) {
    if (action.f != NULL)
        action.f(json);
    if (action.children != NULL)
        visit(action.children, json);
}


void visit(struct json_dispatch actions[], cJSON *json) {
    for (int i =0; actions[i].name != NULL; i++) {
        cJSON *subtree = cJSON_GetObjectItem(json, actions[i].name);
        if (cJSON_IsArray(subtree)) {
            cJSON *elem;
            cJSON_ArrayForEach(elem, subtree)
                dispatch(actions[i], elem);
        } else {
            dispatch(actions[i], subtree);
        }
    }
}

void oci_ociVersion(cJSON *json) {
    printf("oci_ociVersion: %s\n", json->valuestring);
}


void oci_env(cJSON *json) {
    printf("oci_env: %s\n", json->valuestring);
}


void oci_cwd(cJSON *json) {
    printf("oci_cwd: %s\n", json->valuestring);
}


void oci_path(cJSON *json) {
    printf("oci_path: %s\n", json->valuestring);
}


void oci_readonly(cJSON *json) {
    // json->root->readonly is a boolean
    const char *bool_to_str;

    if (cJSON_IsTrue(json)) {
        bool_to_str = "true";
    } if (cJSON_IsFalse(json)) {
        bool_to_str = "false";
    }

    printf("oci_readonly: %s\n", bool_to_str);
}
