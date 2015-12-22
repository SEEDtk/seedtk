TOP_DIR = $(KB_TOP)
include tools/Makefile.common

#MODULE_DIRS = $(wildcard modules/*)
#MODULES = $(notdir $(MODULE_DIRS))
MODULES = $(shell $(TOOLS_DIR)/module-order modules)
MODULE_DIRS = $(foreach mod,$(MODULES),modules/$(mod))

#
# Default deplyment target. May be overridden to deploy to an alternative location.
#
TARGET = /kb/deployment
DEPLOY_RUNTIME = /kb/runtime

all: build_modules

what:
	@echo dirs $(MODULE_DIRS)
	@echo modules $(MODULES)

deploy-setup: deploy-dirs deploy-user-env

deploy-dirs:
	-mkdir $(TARGET)
	-mkdir $(TARGET)/bin
	-mkdir $(TARGET)/lib
	-mkdir $(TARGET)/plbin
	-mkdir $(TARGET)/pybin
	-mkdir $(TARGET)/rsbin
	-mkdir $(TARGET)/services

# make the necessary deployment directories
# loop over each module and call its make deploy
# create a user-env.sh and put it in the deployment
# location (TARGET)

deploy: deploy-setup

	for m in $(MODULE_DIRS); do \
		if [ -d $$m ] ; then \
			(cd $$m; make deploy TARGET=$(TARGET) DEPLOY_RUNTIME=$(DEPLOY_RUNTIME) ); \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi  \
		fi \
	done

# make the necessary deployment directories
# loop over each module and call its make deploy
# create a user-env.sh and put it in the deployment
# location (TARGET)

deploy-client: deploy-setup

	for m in $(MODULE_DIRS); do \
		if [ -d $$m ] ; then \
			(cd $$m; make deploy-client TARGET=$(TARGET) DEPLOY_RUNTIME=$(DEPLOY_RUNTIME) ); \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi  \
		fi \
	done

# make the necessary deployment directories
# loop over each module and call its make deploy
# create a user-env.sh and put it in the deployment
# location (TARGET)

deploy-all: deploy-setup

	for m in $(MODULE_DIRS); do \
		if [ -d $$m ] ; then \
			(cd $$m; make deploy-all TARGET=$(TARGET) DEPLOY_RUNTIME=$(DEPLOY_RUNTIME) ); \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi  \
		fi \
	done

deploy-user-env:
	-mkdir $(TARGET)

	dest=$(TARGET)/user-env.sh; \
	q='"'; \
	echo "export KB_TOP=$$q$(TARGET)$$q" > $$dest; \
	echo "export KB_RUNTIME=$$q$(DEPLOY_RUNTIME)$$q" >> $$dest; \
	echo "export KB_PERL_PATH=$$q$(TARGET)/lib$$q" >> $$dest; \
	echo "export PERL5LIB=\$$KB_PERL_PATH:\$$KB_PERL_PATH/perl5" >> $$dest; \
	echo "export PYTHONPATH=$$q\$$KB_PERL_PATH:\$$PYTHONPATH$$q" >> $$dest; \
	echo "export R_LIBS=$$q\$$KB_PERL_PATH:\$$KB_R_PATH$$q" >> $$dest; \
	echo "export JAVA_HOME=$$q\$$KB_RUNTIME/java$$q" >> $$dest; \
	echo "export CATALINA_HOME=$$q\$$KB_RUNTIME/tomcat$$q" >> $$dest; \
	echo "export PATH=$$q\$$JAVA_HOME/bin:\$$KB_TOP/bin:\$$KB_RUNTIME/bin:\$$PATH$$q" >> $$dest;

	dest=$(TARGET)/user-env.csh; \
	q='"'; \
	echo "setenv KB_TOP $$q$(TARGET)$$q" > $$dest; \
	echo "setenv KB_RUNTIME $$q$(DEPLOY_RUNTIME)$$q" >> $$dest; \
	echo "setenv KB_PERL_PATH $$q$(TARGET)/lib$$q" >> $$dest; \
	echo "setenv PERL5LIB \$${KB_PERL_PATH}:\$$KB_PERL_PATH/perl5" >> $$dest; \
	echo "if (\$$?PYTHONPATH) then" >> $$dest; \
	echo "   setenv PYTHONPATH $$q\$${KB_PERL_PATH}:\$$PYTHONPATH$$q" >> $$dest; \
	echo "else" >> $$dest; \
	echo "   setenv PYTHONPATH $$q\$${KB_PERL_PATH}$$q" >> $$dest; \
	echo "endif" >> $$dest; \
	echo "if (\$$?KB_R_PATH) then" >> $$dest; \
	echo "    setenv R_LIBS $$q\$${KB_PERL_PATH}:\$$KB_R_PATH$$q" >> $$dest; \
	echo "else" >> $$dest; \
	echo "    setenv R_LIBS $$q\$${KB_PERL_PATH}$$q" >> $$dest; \
	echo "endif" >> $$dest; \
	echo "setenv JAVA_HOME $$q\$$KB_RUNTIME/java$$q" >> $$dest; \
	echo "setenv CATALINA_HOME $$q\$$KB_RUNTIME/tomcat$$q" >> $$dest; \
	echo "setenv PATH $$q\$$JAVA_HOME/bin:\$$KB_TOP/bin:\$$KB_RUNTIME/bin:\$$PATH$$q" >> $$dest;

	dest=$(TARGET)/service-env.sh ; \
	q='"'; \
	echo "source $(TARGET)/user-env.sh;" > $$dest; \
	echo "for i in $(TARGET)/services/*/bin; do" >> $$dest; \
	echo "   export PATH=$q\$${PATH}:\$$i$q;" >> $$dest; \
	echo "done" >> $$dest

	dest=$(TARGET)/service-env.csh ; \
	q='"'; \
	echo "source $(TARGET)/user-env.csh;" > $$dest; \
	echo "foreach i ($(TARGET)/services/*/bin)" >> $$dest; \
	echo "   setenv PATH $q\$${PATH}:\$$i$q;" >> $$dest; \
	echo "end" >> $$dest

# this is called by the default target (make with no target provided)
# the modules will be deployed in the dev_container
# make the necessary directoris
# loop over each module and call its make file with no target (default target)
build_modules:
	if [ ! -d bin ] ; then mkdir bin ; fi
	for m in $(MODULE_DIRS); do \
		if [ -d $$m ] ; then \
			echo "Build $$m" ; \
			(cd $$m; make ) ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

test:
	# foreach module in modules, call make test on that module
	for m in $(MODULE_DIRS); do \
		if [ -d $$m ] ; then \
			(cd $$m; make test DEPLOY_RUNTIME=$(DEPLOY_RUNTIME) ) ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

clean:
	rm -rf $(TARGET)

realclean:
	-rm -rf $(TARGET)
	-rm -rf modules/*
	-rm -rf bin
	-rm runtime
	-rm user-env.*
