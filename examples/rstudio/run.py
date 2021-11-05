import subprocess
# Running rstudio as a background process with & causes BATS to hang
# Forking it as a subprocess instead avoids this issue
subprocess.Popen(['/rstudio/start_rstudio', '8991'])
