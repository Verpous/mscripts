#! python

import argparse
import os
import time
import socket
import select
import webbrowser
import traceback
import abc
import typing

from selenium import webdriver
from selenium.common.exceptions import NoSuchElementException
from selenium.common.exceptions import ElementClickInterceptedException
from selenium.webdriver.common.by import By
from selenium.webdriver.remote.webdriver import WebDriver
from selenium.webdriver.remote.webelement import WebElement
from selenium.webdriver.chromium.options import ChromiumOptions

AUTO = 'auto'
CHROME = 'chrome'
EDGE = 'edge'
FIREFOX = 'firefox'

class BrowserController(abc.ABC):
    @abc.abstractmethod
    def set_profile(self, profile: str) -> None:
        pass

    @abc.abstractmethod
    def launch(self) -> WebDriver:
        pass

class ChromeController(BrowserController):
    # Since Edge is also chromium-based, it shares a lot of code with Chrome.
    @classmethod
    def set_chromium_basic_options(cls, options: ChromiumOptions) -> None:
        options.add_argument('--no-sandbox') # Otherwise get an error.
        options.add_experimental_option('excludeSwitches', ['enable-logging']) # Suppress annoying startup message.

    @classmethod
    def set_chromium_profile(cls, options: ChromiumOptions, profile: str) -> None:
        # When you set user-data-dir to a dir that is already in use, this doesn't work. There's no solution but to create a copy of the profile which I don't want to do.
        # Instead users should be suggested to either use Firefox, or create a new profile exclusively for this.
        user_data_dir = os.path.dirname(profile)
        profile_directory = os.path.basename(profile)
        options.add_argument(f'--user-data-dir={user_data_dir}')
        options.add_argument(f'--profile-directory={profile_directory}')

    def __init__(self) -> None:
        self.options = webdriver.ChromeOptions()
        ChromeController.set_chromium_basic_options(self.options)

    def set_profile(self, profile: str) -> None:
        ChromeController.set_chromium_profile(self.options, profile)

    def launch(self) -> WebDriver:
        return webdriver.Chrome(options=self.options)
        
class EdgeController(BrowserController):
    def __init__(self):
        self.options = webdriver.EdgeOptions()
        ChromeController.set_chromium_basic_options(self.options)

    def set_profile(self, profile: str) -> None:
        ChromeController.set_chromium_profile(self.options, profile)

    def launch(self) -> WebDriver:
        return webdriver.Edge(options=self.options)

class FirefoxController(BrowserController):
    def __init__(self):
        self.options = webdriver.FirefoxOptions()

    def set_profile(self, profile: str) -> None:
        # Takes a super long time to load fat profiles, and there's no way around it. Users are advised to create a lean profile just for this.
        self.options.profile = profile

    def launch(self) -> WebDriver:
        return webdriver.Firefox(options=self.options)

def get_default_browser() -> str:
    try:
        import winreg
        
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\\Microsoft\\Windows\\Shell\\Associations\\UrlAssociations\\http\\UserChoice") as key:
            browser_id = winreg.QueryValueEx(key, 'ProgId')[0]

        if 'ChromeHTML' in browser_id:
            return CHROME
        elif 'AppXq0fevzme2pys62n3e0fbqa7peapykr8v' in browser_id: # WTF Microsoft.
            return EDGE
        elif 'FirefoxURL' in browser_id:
            return FIREFOX
    except ModuleNotFoundError:
        # On Windows this is an empty string, thanks webbrowser.
        browser_name = webbrowser.get().name

        for name in (CHROME, EDGE, FIREFOX):
            if name in browser_name:
                return name

    # Default to edge. Sorry linux users.
    return EDGE

def do_with_retries(action: typing.Callable[[], typing.Any], num_retries: int = 10, sleep_between_retries: float = 1.0) -> typing.Any:
    for i in range(num_retries):
        try:
            return action()
        except:
            if i == num_retries - 1:
                raise

            time.sleep(sleep_between_retries)

def is_alive(driver: WebDriver) -> bool:
    try:
        driver.title
        return True
    except:
        return False

def click_export_button(driver: WebDriver, export_button: WebElement) -> None:
    # Annoying popup that asks you to sign in hides the export button sometimes.
    try:
        export_button.click()
    except ElementClickInterceptedException:
        close_popup_button = driver.find_element(By.XPATH, "//button[@aria-label='Close']")
        close_popup_button.click()
        raise

def get_download_button(driver: WebDriver) -> WebElement:
    # Try obtain the "in progress" text from the page. If it's there, that means the list isn't ready yet so we raise an exception.
    try:
        driver.find_element(By.XPATH, "//span[text()='In progress']")
        raise Exception('Still in progress')
    # If there's no more "in progress" element in the page, we return the topmost download button.
    except NoSuchElementException:
        return driver.find_element(By.XPATH, "//button[contains(@aria-label, 'Start download for')]")
    # If still in progress or failed to find it due to an unexpected exception type, refresh the page and propagate the exception so we'll retry.
    except:
        driver.refresh()
        raise

def export_list(driver: WebDriver, list_id: str) -> None:
    driver.get(f'https://www.imdb.com/list/ls{list_id}')

    # Begin exporting.
    export_button = do_with_retries(
        lambda: driver.find_element(By.XPATH, "//button[@aria-label='Export']"))
    do_with_retries(lambda: click_export_button(driver, export_button))

    # Go to exports page once the popup tells us.
    exports_page_link = do_with_retries(
        lambda: driver.find_element(By.XPATH, "//a[@aria-label='Open exports page']"))
    do_with_retries(exports_page_link.click)

    # Hit the download button once the list is ready.
    download_button = do_with_retries(lambda: get_download_button(driver))
    do_with_retries(download_button.click)

def main() -> None:
    # Open the socket ASAP to minimize chances of someone sending a message into the void.
    # I wanted to receive commands from stdin which is redirected to a fifo, but that fails due to probably a bug with mingw. So we use a UDP server instead.
    host = '127.0.0.1'
    port = 42069
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((host, port))

    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description='''Acts as a server that you can request to download IMDb lists from.
    Write IMDb list IDs to stdin separated by newlines, and it will download each list once it's written.
    It's the client's responsibility to monitor the downloads folder for the downloaded files.''')
    parser.add_argument('-b', '--browser', choices=(AUTO, CHROME, EDGE, FIREFOX), default=AUTO, action='store', help='Choose which browser to use.')
    parser.add_argument('-p', '--profile', metavar='PROFILE', default='', action='store', help=
        "Path to the browser profile to use. Good for using a profile where you're signed in to IMDb so you can download private lists.")
    args = parser.parse_args()

    browser_name = get_default_browser() if args.browser == AUTO else args.browser

    # Match statements suck. Don't try to refactor this.
    controller = (
        ChromeController() if browser_name == CHROME else
        EdgeController() if browser_name == EDGE else
        FirefoxController() if browser_name == FIREFOX else
        None
    )

    assert controller is not None

    # Use empty instead of None as default because it's easier for callers to use.
    if args.profile != '':
        controller.set_profile(args.profile)

    # RATIONALE: we spin a server instead of running this script once per list ID because launching the browser takes time and we don't want to pay that cost multiple times.
    # NOTE: I wanted to minimize the browser window but it causes things to fail.
    with controller.launch() as driver:
        while True:
            # We use select so we can have a timeout and check if the browser is still alive.
            readable, _, _ = select.select((sock,), (), (), 1)

            # "for s in readable" would have the same effect except if we get 'quit' break will only break out of the inner loop.
            if len(readable) > 0:
                data, _ = sock.recvfrom(1024)
                list_id = data.decode().strip()

                if list_id == 'quit':
                    break

                try:
                    export_list(driver, list_id)
                except:
                    traceback.print_exc()

            assert is_alive(driver)

if __name__ == '__main__':
    main()
