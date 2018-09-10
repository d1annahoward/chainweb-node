{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE BangPatterns #-}

-- |
-- Module: Chainweb.ChainStore.HashMap
-- Copyright: Copyright © 2018 Kadena LLC.
-- License: MIT
-- Maintainer: Lars Kuhtz <lars@kadena.io>
-- Stability: experimental
--
-- Implements "Chainweb.ChainDB"
--
module Chainweb.ChainDB.HashMap
(
-- * Chain Database Handle
  Configuration(..)
, ChainDb
, initChainDb
, closeChainDb

-- * Validation Status
, ValidationStatus(..)

-- * Entry Type
, Key
, Entry
, key
, parent
, rank
, uncheckedKey
, uncheckedEntry
, decideKeyStatus
, decideEntryStatus
, KeySet

-- * Updates
, Updates
, updates
, updatesFrom
, updatesNext

-- * Pure Database Snapshot
, Snapshot
, snapshot
, syncSnapshot

-- * Queries
, branches
, children
, getEntry
, getEntryIO
, getEntrySync
, lookupEntry

-- * Insertion
, insert

-- * Serialization
, encodeEntry
, decodeEntry

-- * Persistence
, persist

-- * Exceptions
, DbException(..)

-- * implementation specific
, entry
, dbKey
, dbEntry
) where

import Control.Concurrent.MVar
import Control.Concurrent.STM
import Control.Lens hiding (children)
import Control.Monad
import Control.Monad.Catch
import Control.Monad.Trans.Resource (runResourceT)

import Data.Foldable (traverse_)
import Data.Hashable (Hashable(..))
import Data.Kind
import Data.Monoid
import Data.Sequence (Seq)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Streaming as B
import qualified Data.HashMap.Strict as HM
import qualified Data.HashSet as HS
import qualified Data.List as L
import qualified Data.Sequence as Seq

import Numeric.Natural


import Streaming
import qualified Streaming.Prelude as S

import System.Path (Path, Absolute, toFilePath)

-- internal imports

import qualified Chainweb.ChainDB.Entry as E

-- -------------------------------------------------------------------------- --
-- Internal DB Representation

type ChildrenMap = HM.HashMap E.Key (HS.HashSet E.Key)

data Db = Db
    { _dbEntries :: !(HM.HashMap E.Key E.Entry)
    , _dbBranches :: !(HS.HashSet E.Key)
    , _dbChildren :: !ChildrenMap
    }

makeLenses ''Db

-- | Unchecked addition
--
-- ASSUMES that
--
-- * Item is not yet in database
--
-- Guarantees that
--
-- * each item without children is included in branches and
-- * each item is included in children
--
dbAdd :: E.Entry -> Db -> Db
dbAdd e db = db
    & dbEntries %~ HM.insert (E.key e) e
    & dbBranches %~ dbAddBranch e
    & dbChildren %~ dbAddChildren e

dbAddCheckedInternal :: MonadThrow m => E.Entry -> Db -> m Db
dbAddCheckedInternal e db = case E.parent e of
    Nothing -> return $ dbAdd e db
    Just p -> case HM.lookup p (_dbEntries db) of
        Nothing -> throwM $ ParentMissing (UncheckedEntry e)
        Just pe -> do
            unless (E.rank e == E.rank pe + 1)
                $ throwM $ InvalidRank (UncheckedEntry e)
            return $ dbAdd e db

dbAddChecked_ :: MonadThrow m => E.Entry -> Db -> m (Db, Maybe E.Key)
dbAddChecked_ e db
    | isMember = return (db, Nothing)
    | otherwise = (, Just k) <$> dbAddCheckedInternal e db
  where
    k = E.key e
    isMember = HM.member k (_dbEntries db)

dbAddChecked :: MonadThrow m => E.Entry -> Db -> m Db
dbAddChecked e db = fst <$> dbAddChecked_ e db

dbAddBranch :: E.Entry -> HS.HashSet E.Key -> HS.HashSet E.Key
dbAddBranch e bs = HS.insert (E.key e)
    $ maybe bs (flip HS.delete bs) (E.parent e)

dbAddChildren :: E.Entry -> ChildrenMap -> ChildrenMap
dbAddChildren e cs = HM.insert k mempty $ case E.parent e of
    Just p -> HM.insertWith (<>) p (HS.singleton k) cs
    _ -> cs
  where
    k = E.key e

-- -------------------------------------------------------------------------- --
-- Exceptions

data DbException
    = ValidationFailed (Entry 'Unchecked) SomeException
    | ParentMissing (Entry 'Unchecked)
    | InvalidRank (Entry 'Unchecked)
    | DeserializationFailure SomeException
    deriving (Show)

instance Exception DbException

-- -------------------------------------------------------------------------- --
-- Chain Database Handle

data Configuration = Configuration
    { _configRoot :: !E.Entry
    }

data ChainDb = ChainDb
    { _getDb :: MVar Db
    , _dbEnumeration :: !(TVar (Seq.Seq (Key 'Checked)))
    }

initChainDb :: Configuration -> IO ChainDb
initChainDb config = ChainDb
    <$> newMVar (dbAdd root emptyDb)
    <*> newTVarIO (Seq.singleton (CheckedKey $ E.key root))
  where
    root = _configRoot config
    emptyDb = Db mempty mempty mempty

closeChainDb :: ChainDb -> IO ()
closeChainDb = void . takeMVar . _getDb

-- -------------------------------------------------------------------------- --
-- Validation Status

data ValidationStatus = Unchecked | Checked

-- -------------------------------------------------------------------------- --
-- Entry Type

data Key :: ValidationStatus -> Type where
    UncheckedKey :: E.Key -> Key 'Unchecked
    CheckedKey :: E.Key -> Key 'Checked

deriving instance Show (Key s)
deriving instance Eq (Key s)
deriving instance Ord (Key s)

dbKey :: Key s -> E.Key
dbKey (UncheckedKey k) = k
dbKey (CheckedKey k) = k

instance Hashable (Key s) where
    hashWithSalt s (UncheckedKey k) = hashWithSalt s k
    hashWithSalt s (CheckedKey k) = hashWithSalt s k

data Entry :: ValidationStatus -> Type where
    UncheckedEntry :: E.Entry -> Entry 'Unchecked
    CheckedEntry :: E.Entry -> Entry 'Checked

deriving instance Show (Entry s)
deriving instance Eq (Entry s)

entry :: E.Entry -> Entry 'Unchecked
entry = UncheckedEntry

dbEntry :: Entry s -> E.Entry
dbEntry (UncheckedEntry e) = e
dbEntry (CheckedEntry e) = e

key :: Entry s -> Key s
key (UncheckedEntry e) = UncheckedKey $ E.key e
key (CheckedEntry e) = CheckedKey $ E.key e

parent :: Entry s -> Maybe (Key s)
parent (UncheckedEntry e) = UncheckedKey <$> E.parent e
parent (CheckedEntry e) = CheckedKey <$> E.parent e

rank :: Entry s -> Natural
rank = E.rank . dbEntry

uncheckedKey :: Key s -> Key 'Unchecked
uncheckedKey = UncheckedKey . dbKey

uncheckedEntry :: Entry s -> Entry 'Unchecked
uncheckedEntry  = UncheckedEntry . dbEntry

decideKeyStatus :: Key s -> Either (Key 'Unchecked) (Key 'Checked)
decideKeyStatus k@UncheckedKey{} = Left k
decideKeyStatus k@CheckedKey{} = Right k

decideEntryStatus :: Entry s -> Either (Entry 'Unchecked) (Entry 'Checked)
decideEntryStatus e@UncheckedEntry{} = Left e
decideEntryStatus e@CheckedEntry{} = Right e

type KeySet (s :: ValidationStatus) = HS.HashSet (Key s)

-- -------------------------------------------------------------------------- --
-- Updates

data Updates = Updates
    { _updatesCursor :: !(TVar Int)
    , _updatesEnum :: !(TVar (Seq (Key 'Checked)))
    }

updates :: ChainDb -> IO Updates
updates db = Updates
    <$> newTVarIO 0
    <*> pure (_dbEnumeration db)

-- FIXME improve performance
--
updatesFrom :: ChainDb -> Key 'Checked -> IO Updates
updatesFrom db k = do
    enumeration <- readTVarIO enumVar
    idx <- case Seq.elemIndexL k enumeration of
        Just i -> return i
        Nothing -> error "TODO: Internal invariant violation"
    Updates
        <$> newTVarIO idx
        <*> pure enumVar
  where
    enumVar = _dbEnumeration db

updatesNext :: Updates -> STM (Key 'Checked)
updatesNext u = do
    xs <- readTVar (_updatesEnum u)
    c <- readTVar (_updatesCursor u)
    case Seq.lookup c xs of
        Nothing -> retry
        Just x -> do
            writeTVar (_updatesCursor u) (c + 1)
            return x

-- -------------------------------------------------------------------------- --
-- Pure Database Snapshot

data Snapshot = Snapshot
    { _snapshotDb :: !Db
    , _snapshotAdditions :: !(HM.HashMap E.Key E.Entry)
    , _snapshotChainDb :: !ChainDb
    }

makeLenses ''Snapshot

snapshot :: ChainDb -> IO Snapshot
snapshot db@(ChainDb dbVar _) = Snapshot
    <$> readMVar dbVar
    <*> pure mempty
    <*> pure db

syncSnapshot :: Snapshot -> IO Snapshot
syncSnapshot s
    | HM.null (_snapshotAdditions s) = snapshot db
    | otherwise = do

        -- insert entries to db and collect new keys
        --
        news <- modifyMVar (_getDb db)
            $ \x -> foldM
                (\(d, ns) e -> fmap (maybe ns (ns |>)) <$> dbAddChecked_ e d)
                (x, mempty)
                rankedAdditions

        -- publish new keys to updates enumeration
        --
        atomically $ modifyTVar' (_dbEnumeration db)
            $ \x -> x <> (CheckedKey <$> news)

        -- return fresh snapshot
        snapshot db
  where
    db = view snapshotChainDb s
    rankedAdditions = L.sortOn E.rank $ HM.elems $ _snapshotAdditions s

-- -------------------------------------------------------------------------- --
-- Queries

branches :: Snapshot -> KeySet 'Checked
branches = HS.map CheckedKey . _dbBranches . _snapshotDb

children :: Key 'Checked -> Snapshot -> KeySet 'Checked
children k s = case HM.lookup (dbKey k) . _dbChildren $ _snapshotDb s of
    Nothing -> error "TODO internal exception"
    Just c -> HS.map CheckedKey c

getEntry :: Key 'Checked -> Snapshot -> Maybe (Entry 'Checked)
getEntry = lookupEntry

lookupEntry :: Key t -> Snapshot -> Maybe (Entry 'Checked)
lookupEntry k =
    fmap CheckedEntry . HM.lookup (dbKey k) . _dbEntries . _snapshotDb

getEntryIO :: Key 'Checked -> Snapshot -> IO (Entry 'Checked)
getEntryIO k s = case getEntry k s of
    Just c -> return c
    Nothing -> snapshot db >>= \s' -> case getEntry k s' of
        Just c -> return c
        Nothing -> error "TODO internal exception"
  where
    db = view snapshotChainDb s

getEntrySync :: Key 'Checked -> Snapshot -> IO (Snapshot, Entry 'Checked)
getEntrySync = f sync
  where f g k s  = maybe (g k s) (pure . (s,)) $ getEntry k s
        sync k s = syncSnapshot s >>= f die k
        die _ _  = error "Checked Key from a different database used for Snapshot query"

-- -------------------------------------------------------------------------- --
-- Insertion

insert :: MonadThrow m => Entry s -> Snapshot -> m Snapshot
insert e s
    | (E.key dbe) `HM.member` (_dbEntries $ _snapshotDb s) = return s
    | otherwise = s
        & (snapshotAdditions %~ HM.insert (E.key dbe) dbe)
        & snapshotDb (dbAddChecked dbe)
  where
    dbe = dbEntry e

-- -------------------------------------------------------------------------- --
-- Serialization of Entries

encodeEntry :: Entry s -> BS.ByteString
encodeEntry = E.encodeEntry . dbEntry

decodeEntry :: MonadThrow m => BS.ByteString -> m (Entry 'Unchecked)
decodeEntry = fmap UncheckedEntry . E.decodeEntry

-- -------------------------------------------------------------------------- --
-- ChainDb Persistence

-- SECOND ATTEMPT

-- | Write the contents of a `ChainDb` to a given filepath. The entries are
-- written in order of block height, from newest to oldest.
-- persistDb :: Path Absolute -> ChainDb -> IO ()
-- persistDb fp cdb = updates cdb >>= \u -> snapshot cdb >>= f u
--   where f u s   = atomically ((Just <$> updatesNext u) `orElse` pure Nothing) >>= traverse_ (g u s)
--         g u s k = case getEntry k s of
--                     Just e  -> magic fp e >> f u s
--                     Nothing -> syncSnapshot s >>= \s' -> g u s' k

-- | A very dumb way to consume each `Entry`.
-- magic :: Path Absolute -> Entry 'Checked -> IO ()
-- magic (toFilePath -> fp) e = BS.appendFile fp $ encodeEntry e

-- THIRD ATTEMPT

-- | Given a `ChainDb`, stream all the Entries it contains in order of
-- block height, from newest to oldest.
entries :: ChainDb -> Stream (Of (Entry 'Checked)) IO ()
entries db = lift (updates db) >>= \u -> lift (snapshot db) >>= f u
  where f !u !s = do
          e <- lift (atomically $ (Just <$> updatesNext u) `orElse` pure Nothing)
          traverse_ (g u s) e
        g !u !s !k = case getEntry k s of
                       Just e  -> S.yield e >> f u s
                       Nothing -> lift (syncSnapshot s) >>= \s' -> g u s' k

-- | Encode each `Entry` as a base64 `BS.ByteString`.
encoded :: Monad m => Stream (Of (Entry 'Checked)) m () -> Stream (Of BS.ByteString) m ()
encoded = S.map (B64.encode . encodeEntry)
{-# INLINE encoded #-}

-- | Form a ByteString stream from base64-encoded Entries, and divide them by
-- newline characters. A newline byte cannot appear in a base64 encodings, thus
-- making it a unique byte to split on.
separated :: Monad m => Stream (Of BS.ByteString) m () -> B.ByteString m ()
separated = B.fromChunks . S.intersperse (BS.singleton 0x0A)
{-# INLINE separated #-}

persist :: Path Absolute -> ChainDb -> IO ()
persist (toFilePath -> fp) db =
  runResourceT . B.writeFile fp . hoist lift . separated . encoded $ entries db
