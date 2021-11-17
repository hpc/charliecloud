#!/usr/bin/env python3

# This script uses selenium and a headless Firefox to log into RStudio. It
# does not test an actual R computation because we haven't yet figured out how
# to do that; see issue #1238.

import getpass
import os
import sys

import selenium
import selenium.webdriver
import selenium.webdriver.common.proxy

print(">>> reading password")
fp = open(sys.argv[1])
password = fp.readline().rstrip()
fp.close()
print(">>> found password: %s" % password)

# Remove the proxy environment variables. Otherwise, Selenium tries to use the
# proxy to connect to Firefox on localhost (which does not work). I also tried
# to configure Selenium directly to not proxy, but it didn't work.
for key in list(os.environ.keys()):
   if ("proxy" in key.lower()):
      print(">>> deleting env: %s=%s" % (key, os.environ[key]))
      del os.environ[key]

print(">>> starting headless Firefox")
opts = selenium.webdriver.FirefoxOptions()
opts.add_argument("--headless")
drv = selenium.webdriver.Firefox(options=opts, service_log_path="/dev/stdout")
drv.implicitly_wait(30)  # timeout on find_element_by_*

print(">>> fetching login page")
drv.get('http://localhost:8991')

print(">>> got page titled: %s" % drv.title)
assert "Sign In" in drv.title

print(">>> logging in")
elem = drv.find_element_by_name("username")
elem.clear()
elem.send_keys(getpass.getuser())
elem = drv.find_element_by_name("password")
elem.clear()
elem.send_keys(password)
drv.find_element_by_xpath("//button[text()='Sign In']").click()

print(">>> checking for loaded app")
drv.find_element_by_id("rstudio_container")

#print("cleaning up")
#drv.quit()

print(">>> done")  # Selenium cleans up Firefox automatically?
