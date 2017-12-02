Plugins in unsafe dir relies on perl threads which are unsafe in Hexchat (well, at least until 2.12.4 including) because of general thread unsafeness of hexchat internal api. Scripts are working correctly and the only side-effect that occurs - notable memory leak. Looks like threads never release consumed memory.

As a workaround img_url_memc.pl uses external key-value database to store links. Sample image download client (img-save.pl) included to provide working solution.

