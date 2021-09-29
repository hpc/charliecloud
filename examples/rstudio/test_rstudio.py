import getpass
import time
import selenium
from selenium import webdriver
from selenium.webdriver import FirefoxOptions
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

opts = FirefoxOptions()
opts.add_argument("--headless")
driver = webdriver.Firefox(log_path='/tmp/geckodriver.log',firefox_options=opts)
driver.get('http://127.0.0.1:8991')
assert "Sign In" in driver.title
elem = driver.find_element_by_name("username")
elem.clear()
user = getpass.getuser()
elem.send_keys(user)

elem = driver.find_element_by_name("password")
elem.clear()
password = "charliecloud"
elem.send_keys(password)
elem.send_keys(Keys.RETURN)

driver.find_element_by_xpath("//button[text()='Sign In']").click()
time.sleep(30)
try:
    elem = driver.find_element_by_id("rstudio_container")
    print('Good')
except selenium.common.exceptions.NoSuchElementException:
    print('Bad')
