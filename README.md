changelog.pl
============

What is changelog?
------------------

changelog is a Perl script that adds/updates entries in a change log (aka motd). The current version is 0.1b2.

How do I use it?
----------------

Either run

	changelog my entry text

which adds 'my entry text' to today's entry with the currently logged in user.

Or just

	changelog

which will ask you for the entries interactively. You can also enter more than one entry by using the return key.

Other options are:

	-v			verbose output
	-d YYYY-MM-DD		add entry for date YYY-MM-DD
	-u bob			add entry with username bob
	-f /path/to/file	use specified change log file instead of the default one
	-e "commit message"	commit changes to /etc with etckeeper using specified commit message
	-r			reboot system after updating the file
	-s			output the file after updating
	--version		print version
	--help, -h		print help screen 

