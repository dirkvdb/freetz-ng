$(call PKG_INIT_BIN, 1.102.4)
$(PKG)_SOURCE:=tailscale_$($(PKG)_VERSION)_386.tgz
$(PKG)_SITE:=https://pkgs.tailscale.com/stable
$(PKG)_HASH:=44730cacea956ffdbe145e7c1dae05668ca61febdde3ef764bba75d20c8d0b8e
$(PKG)_TARBALL_STRIP_COMPONENTS:=1

$(PKG)_BINARY:=$($(PKG)_DIR)/tailscale
$(PKG)_DAEMON_BINARY:=$($(PKG)_DIR)/tailscaled
$(PKG)_TARGET_BINARY:=$($(PKG)_DEST_DIR)/usr/bin/tailscale
$(PKG)_TARGET_DAEMON_BINARY:=$($(PKG)_DEST_DIR)/usr/sbin/tailscaled

$(PKG)_STARTLEVEL=80

$(PKG_SOURCE_DOWNLOAD)
$(PKG_UNPACKED)
$(PKG_CONFIGURED_NOP)

$($(PKG)_BINARY) $($(PKG)_DAEMON_BINARY): $($(PKG)_DIR)/.configured

$($(PKG)_TARGET_BINARY): $($(PKG)_BINARY)
	mkdir -p $(dir $@)
	cp $< $@
	$(TARGET_STRIP) $@
	chmod 755 $@

$($(PKG)_TARGET_DAEMON_BINARY): $($(PKG)_DAEMON_BINARY)
	mkdir -p $(dir $@)
	cp $< $@
	$(TARGET_STRIP) $@
	chmod 755 $@

$(pkg)-precompiled: $($(PKG)_TARGET_BINARY) $($(PKG)_TARGET_DAEMON_BINARY)

$(pkg)-clean:

$(pkg)-uninstall:
	$(RM) $($(PKG)_TARGET_BINARY) $($(PKG)_TARGET_DAEMON_BINARY)

$(PKG_FINISH)
