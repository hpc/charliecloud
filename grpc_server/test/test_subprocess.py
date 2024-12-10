import subprocess

test = subprocess.check_output(['ch-run', '--version'])
print(test)
