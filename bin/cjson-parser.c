
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cjson/cJSON.h>

void readJSONFile(const char *filename);
void iterJSONFile(cJSON *json);

int main() {
    const char *filename = "config.json";
    readJSONFile(filename);
    return 0;
}

void iterJSONFile(cJSON *json) {
 
    cJSON *proc_key = cJSON_GetObjectItemCaseSensitive(json, "process");
    cJSON *root_key = cJSON_GetObjectItemCaseSensitive(json, "root");

    json = json->child;

    while (json != NULL) {
        if (strcmp(json->string, "ociVersion") == 0) {
            // validate oci Version
            printf("ociVersion: %s\n", json->valuestring);
        } else if (strcmp(json->string, "process") == 0) {
            // child: env - set environment to PATH value, cwd corresponds to --cd
            cJSON *env_key = cJSON_GetObjectItemCaseSensitive(proc_key, "env");
            printf("process env: %s\n", env_key->child->valuestring);
            printf("process env: %s\n", env_key->child->next->valuestring);
            cJSON *cwd_key = cJSON_GetObjectItemCaseSensitive(proc_key, "cwd");
            printf("process cwd: %s\n", cwd_key->valuestring);
        } else if (strcmp(json->string, "root") == 0) {
            // child: path (map to newroot in ch-run.c), readonly (ignore for now)
            cJSON *path_key = cJSON_GetObjectItemCaseSensitive(root_key, "path");
            printf("root path: %s\n", path_key->valuestring);
            cJSON *read_key = cJSON_GetObjectItemCaseSensitive(root_key, "readonly");
            //printf("root readonly: %s\n", read_key->valuestring);
        } else if (strcmp(json->string, "hostname") == 0) {
            printf("hostname key identified.\n");
            // ignore
        } else if (strcmp(json->string, "mounts") == 0) {
            printf("mounts key identified.\n");
            // check mount(2)
        } else if (strcmp(json->string, "linux") == 0) {
            printf("linux key identified.\n");
        } else {
            printf("key name %s NOT identified.\n", json->string);
        }
        json = json->next;
    }
}

void readJSONFile(const char *filename) {

    FILE *file = fopen(filename, "r");
    long length = 0;
    char *buffer = NULL;
    
    if (file == NULL) {
        fprintf(stderr, "Error: could not open file %s\n", filename);
        return;
    }

    // Get the file length
    fseek(file, 0, SEEK_END);
    length = ftell(file);
    fseek(file, 0, SEEK_SET);
    // Allocate content buffer
    buffer = (char *)malloc((size_t)length + sizeof(""));
    fread(buffer, sizeof(char), (size_t)length, file);
    // Null-terminate the string
    buffer[length] = '\0';

    fclose(file);

    // Parse the JSON data
    cJSON *json = cJSON_Parse(buffer);
    // Check if parsing was successful
    if (json == NULL) {
        const char *error_ptr = cJSON_GetErrorPtr();
        if (error_ptr != NULL) {
            fprintf(stderr, "Error before: %s\n", error_ptr);
        }
        cJSON_Delete(json);
        free(buffer);
        return;
    }

    // Print the JSON data
    char *json_tree = cJSON_Print(json);
    if (json_tree == NULL)
    {
        fprintf(stderr, "Failed to print JSON tree.\n");
    }
    //printf("%s\n", json_tree);

    // Process the JSON data
    iterJSONFile(json);

    // Clean up
    cJSON_Delete(json);
    free(buffer);
    free(json_tree);
}
