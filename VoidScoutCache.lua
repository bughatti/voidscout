-- VoidScoutCache.lua — synced data from api.voidscout.io
--
-- This file is overwritten by the companion uploader's sync command.
-- The addon reads it on PLAYER_LOGIN and merges into VoidScoutDB.scores
-- if the cache timestamp is newer than the last applied cache.
--
-- WoW does NOT manage this file (it's not a SavedVariable). That means
-- reloads / logouts will NOT overwrite it — only the sync script touches it.
--
-- Default stub: cache is empty until the sync script populates it.

VoidScoutCache = nil
