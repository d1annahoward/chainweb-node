{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeOperators #-}

-- |
-- Module: Chainweb.Pact.Service.Http.Types
-- Copyright: Copyright © 2018 Kadena LLC.
-- License: See LICENSE file
-- Maintainer: Mark Nichols <mark@kadena.io>
-- Stability: experimental
--
-- Types module for Pact execution HTTP API

module Chainweb.Pact.Service.Http.Types
    ( LocalEnv(..), rieReqQ
    , pactAPI
    , PactAPI
    , PactAppM
    ) where

import Control.Concurrent.STM.TQueue
import Control.Lens
import Control.Monad.Trans.Reader

import Data.Text (Text)

import Servant

import Chainweb.Pact.Service.Types
import Chainweb.Pact.Types

import Pact.Types.Command

-- TODO: Input, possibly output type will change for use with 'local' command
type PactAPI = "local" :> ReqBody '[JSON] (Command Text) :> Post '[JSON] (Either PactException FullLogTxOutput)

data LocalEnv = LocalEnv {_rieReqQ :: (TQueue RequestMsg)}

type PactAppM = ReaderT LocalEnv Handler

pactAPI :: Proxy PactAPI
pactAPI = Proxy

makeLenses ''LocalEnv
