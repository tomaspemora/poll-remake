.PHONY: dummy_translations extract_translations help pull_translations push_translations

.DEFAULT_GOAL := help

FIREFOX_VERSION := "94.0.1"
FIREFOX_LINUX_ARCH := $(shell uname -m)

help: ## display this help message
	@echo "Please use \`make <target>' where <target> is one of"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}'

clean: ## remove generated byte code, coverage reports, and build artifacts
	find . -name '__pycache__' -exec rm -rf {} +
	find . -name '*.pyc' -exec rm -f {} +
	find . -name '*.pyo' -exec rm -f {} +
	find . -name '*~' -exec rm -f {} +

	find poll/translations -name djangojs.mo -exec rm -f {} +
	find poll/translations -name djangojs.po -exec rm -f {} +
	find poll/translations -name textjs.mo -exec rm -f {} +

	coverage erase
	rm -fr build/
	rm -fr dist/
	rm -fr *.egg-info

quality: ## check coding style with pycodestyle and pylint
	pycodestyle poll --max-line-length=120
	pylint poll

node_requirements: ## Install requirements for handlebar templates i18n extraction
	npm install

python_requirements: ## install development environment requirements
	pip install -r requirements.txt --exists-action w
	pip install -r requirements-dev.txt --exists-action w
	cd ./src/xblock-sdk && \
		pip install -r requirements/base.txt && \
		pip install -r requirements/test.txt
	pip install -e .

requirements: node_requirements python_requirements ## install development environment requirements
	@echo "Finished installing requirements."

install_linux_dev_firefox: ## Downloads custom version of firefox for Selenium in Linux
	@echo "This works only on Linux. For MacOS please check the README file"

	rm -rf .firefox .geckodriver
	mkdir .firefox .geckodriver

	curl http://ftp.mozilla.org/pub/firefox/releases/$(FIREFOX_VERSION)/linux-$(FIREFOX_LINUX_ARCH)/en-US/firefox-$(FIREFOX_VERSION).tar.bz2 \
		                --output .firefox/firefox.tar.bz2

	cd .firefox && tar -xvjf firefox.tar.bz2
	cd .geckodriver && wget https://github.com/mozilla/geckodriver/releases/download/v0.15.0/geckodriver-v0.15.0-linux64.tar.gz
	cd .geckodriver && tar -xzf geckodriver-v0.15.0-linux64.tar.gz

linux_dev_test: ## Run tests in development environment to use custom firefox
	PATH=.firefox/firefox/:.geckodriver/:$(PATH) make test

test: ## run tests in the current virtualenv
	mkdir -p var  # for var/workbench.log
	python run_tests.py --with-coverage --cover-package=poll

selfcheck: ## check that the Makefile is well-formed
	@echo "The Makefile is well-formed."

## Localization targets

extract_translations: ## extract strings to be translated, outputting .po files
	rm -rf docs/_build

	# Extract Python and Django template strings
	mkdir -p locale/en/LC_MESSAGES/
	rm -f locale/en/LC_MESSAGES/{django,text}.po
	python manage.py makemessages -l en -v1 -d django
	mv locale/en/LC_MESSAGES/django.po locale/en/LC_MESSAGES/text.po

	@# Note: Intentionally ignoring JS translations in favor of Handlebars
	@#       Keep the line below commented, there is one JavaScript file that has only one
	@#       i18n string is js/poll_edit.js:259 which is (`Saving`)
	@#       already available by other edX platform resources.
	@# django-admin makemessages -l en -v1 -d djangojs -e js

	# Extract Handlebars i18n strings
	> locale/en/LC_MESSAGES/textjs.po  # Ensure it's empty
	# The sort to avoid bash arbitrary file order
	ls poll/public/handlebars/*.handlebars \
	    | xargs node node_modules/.bin/xgettext-template --from-code utf8 \
	        --language Handlebars \
	        --force-po \
	        --output locale/en/LC_MESSAGES/textjs.po

compile_translations: ## compile translation files, outputting .mo files for each supported language
	i18n_tool generate
	python manage.py compilejsi18n
	make clean

detect_changed_source_translations: ## Determines if the source translation files are up-to-date, otherwise exit with a non-zero code.
	i18n_tool changed

pull_translations: ## pull translations from Transifex
	i18n_tool transifex pull
	make compile_translations

push_translations: extract_translations ## push source translation files (.po) to Transifex
	tx push -s

dummy_translations: ## generate dummy translation (.po) files
	i18n_tool dummy

build_dummy_translations: extract_translations dummy_translations compile_translations ## generate and compile dummy translation files

validate_translations: build_dummy_translations detect_changed_source_translations ## validate translations
