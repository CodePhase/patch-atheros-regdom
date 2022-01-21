# patch-atheros-regdom
Modify the atheros wireless driver to enable the card to initiate radiation (IR) on 5GHz bands for AP mode

The Atheros Wifi card driver in Linux prohibits IR on 5GHz channels if the burned-in EEPROM is set to a 'world' domain.  This makes it very difficult to use as a Linux-based access point for 5GHz wifi types like 802.11a, 802.11n, and 802.11ac.  A patch was developed by the OpenWRT community to enable IR on these bands by modifying the Atheros driver.  Unfortunately this patch no longer works in current Linux kernels.

Inspired by the first post from https://github.com/twisteroidambassador/arch-linux-ath-user-regd/issues/1, I have created a new patch and installer script for later Linux kernels that will (almost) have the same effect as before.  By (almost), I mean that the DFS bands are still 'no IR' with this patch.

That said, all responsibility and consequences of using this patch, scripts, and any other software I provide are assumed by the individual using them.  I am providing this content with no warranties and no legal responsibility whatsoever for its use and any damages it may cause.  In other words, use at your own risk.
