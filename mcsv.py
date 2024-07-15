#! python

# USAGE: run mcsv.py <list-id> <downloads-dir> and it will download the list CSV using Firefox, and print the name of the downloaded file.

# TODO: Sign in so we get personal ratings data, and fix bug where sometimes some button is obscured?

import sys
import argparse
import os
import time
import glob

from selenium import webdriver
from selenium.webdriver.common.by import By

class Timeout:
    def __init__(self, timeout_secs=float('inf'), operation='N/A'):
        self._timeout_secs = timeout_secs
        self._operation = operation
        self._enter_time = float('nan')

    def tick(self):
        if time.time() - self._enter_time > self._timeout_secs:
            raise TimeoutError(f"Operation: {self._operation} timed out after: {self._timeout_secs} seconds.")

    def __enter__(self):
        self._enter_time = time.time()
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self._enter_time = float('nan')

def get_latest_in_downloads():
    files_in_dowloads = glob.glob(os.path.join(downloads_dir, '*.csv'))
    latest_file = max(files_in_dowloads, key=os.path.getctime, default=None)
    return latest_file

def do_with_retries(action, num_retries=10, sleep_between_retries=1):
    for i in range(num_retries):
        try:
            return action()
        except:
            if i == num_retries - 1:
                raise

            time.sleep(sleep_between_retries)

list_id = sys.argv[1]
downloads_dir = sys.argv[2]

with webdriver.Firefox() as driver:
    driver.get(f'https://www.imdb.com/list/ls{list_id}')

    # Annoying popup that asks you to sign in hides the export button.
    close_popup_button = do_with_retries(
        lambda: driver.find_element(By.XPATH, "//button[@aria-label='Close']"))
    do_with_retries(close_popup_button.click)

    # Begin exporting.
    export_button = do_with_retries(
        lambda: driver.find_element(By.XPATH, "//button[@aria-label='Export']"))
    do_with_retries(export_button.click)

    # Go to exports page once the popup tells us.
    exports_page_link = do_with_retries(
        lambda: driver.find_element(By.XPATH, "//a[@aria-label='Open exports page']"))
    do_with_retries(exports_page_link.click)

    # Hit the download button once the list is ready.
    def get_download_button():
        driver.refresh()
        return driver.find_element(By.XPATH, "//button[contains(@aria-label, 'Start download for')]")

    download_button = do_with_retries(get_download_button)

    # Wait for the file to be downloaded before calling it a wrap.
    with Timeout(20, 'download CSV') as timeout:
        latest_file_before = get_latest_in_downloads()
        do_with_retries(download_button.click)

        # We hit a button in the browser that should download a CSV. Now we'll monitor the downloads directory until the latest CSV there is different than what it was before.
        # When that happens, we will have the CSV that was downloaded.
        while (latest_file := get_latest_in_downloads()) == latest_file_before or latest_file is None:
            timeout.tick()

        # When the file is created it's sometimes empty for a bit. At some point it jumps to being fully written, without any inbetween.
        # So this waits for the file size to not be zero.
        while True:
            # This sleep is meant to alleviate a problem that is way too much to explain so just see my question about it on StackOverflow:
            # https://stackoverflow.com/questions/78300917/checking-the-size-of-a-file-thats-being-downloaded-by-the-browser-causes-it-to
            time.sleep(1)

            if os.path.getsize(latest_file) != 0:
                break

            try:
                timeout.tick()
            except TimeoutError:
                # For the same reason as the sleep above, we do a trick: we'll check if a different file with a similar name has appeared, and return it.
                latest_file_last_minute = get_latest_in_downloads()

                if (latest_file_last_minute is not None
                        and latest_file_last_minute != latest_file
                        and latest_file.removesuffix('.csv') in latest_file_last_minute
                        and os.path.getsize(latest_file_last_minute) != 0):
                    os.remove(latest_file)
                    latest_file = latest_file_last_minute
                    break

                raise

print(os.path.basename(latest_file))
