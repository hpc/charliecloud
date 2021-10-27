import time
import os
import getpass
import selenium
import selenium.webdriver 

# This script uses selenium to test if RStudio server is working. 
# It signs in with the username and password. 

# Sets up the firefox driver and runs it in headless mode with no GUI
opts = selenium.webdriver.FirefoxOptions()
opts.add_argument("--headless")
tmp_dir = os.environ['BATS_TMPDIR']
driver = selenium.webdriver.Firefox(log_path='%s/geckodriver.log' % tmp_dir, 
        firefox_options=opts)
driver.get('http://127.0.0.1:8991')
assert "Sign In" in driver.title
# Fill in the username and password fields on the page
elem = driver.find_element_by_name("username")
elem.clear()
user = getpass.getuser()
elem.send_keys(user)

elem = driver.find_element_by_name("password")
elem.clear()
password = "charliecloud"
elem.send_keys(password)

# Presses the button to sign in
driver.find_element_by_xpath("//button[text()='Sign In']").click()

# Sleep since it takes a while for the javascript to load in Rstudio web app
time.sleep(30)
try:
    # Look for the rstudio_container id one of the main elements of the app
    # If this isn't there the app failed to login successfully
    elem = driver.find_element_by_id("rstudio_container")
    print('Rstudio login successful!')
except selenium.common.exceptions.NoSuchElementException:
    print('Rstudio login failed!')
finally:
    driver.close()
    driver.quit()
