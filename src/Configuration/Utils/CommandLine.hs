{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UnicodeSyntax #-}

-- |
-- Module: Configuration.Utils.CommandLine
-- Description: Command Line Option Parsing with Default Values
-- Copyright: Copyright © 2015 PivotCloud, Inc.
-- License: MIT
-- Maintainer: Lars Kuhtz <lkuhtz@pivotmail.com>
-- Stability: experimental
--
-- This module provides tools for defining command line parsers for
-- configuration types.
--
-- Unlike /normal/ command line parsers the parsers for configuration
-- types are expected to yield an update function that takes
-- a value and updates the value with the settings from the command line.
--
-- Assuming that
--
-- * all configuration types are nested Haskell records or
--   simple types and
--
-- * that there are lenses for all record fields
--
-- usually the operators '.::' and '%::' are all that is needed from this module.
--
-- The module "Configuration.Utils.Monoid" provides tools for the case that
-- a /simple type/ is a container with a monoid instance, such as @List@ or
-- @HashMap@.
--
-- The module "Configuration.Utils.Maybe" explains the usage of optional
-- 'Maybe' values in configuration types.
--
module Configuration.Utils.CommandLine
( MParser
, (.::)
, (%::)

-- * Misc Utils
, boolReader
, boolOption
, fileOption
, eitherReadP
, module Options.Applicative
) where

import Configuration.Utils.Internal
import Configuration.Utils.Operators

import Control.Applicative
import Control.Monad.Writer hiding (mapM_)

import qualified Data.CaseInsensitive as CI
import Data.Monoid.Unicode
import Data.String
import qualified Data.Text as T

import Options.Applicative hiding (Parser, Success)
import qualified Options.Applicative.Types as O

import qualified Options.Applicative as O

import Prelude hiding (concatMap, mapM_, any)

import qualified Text.ParserCombinators.ReadP as P hiding (string)

import Prelude.Unicode

-- -------------------------------------------------------------------------- --
-- Applicative Option Parsing with Default Values

-- | Type of option parsers that yield a modification function.
--
type MParser α = O.Parser (α → α)

-- | An operator for applying a setter to an option parser that yields a value.
--
-- Example usage:
--
-- > data Auth = Auth
-- >     { _user ∷ !String
-- >     , _pwd ∷ !String
-- >     }
-- >
-- > user ∷ Functor φ ⇒ (String → φ String) → Auth → φ Auth
-- > user f s = (\u → s { _user = u }) <$> f (_user s)
-- >
-- > pwd ∷ Functor φ ⇒ (String → φ String) → Auth → φ Auth
-- > pwd f s = (\p → s { _pwd = p }) <$> f (_pwd s)
-- >
-- > -- or with lenses and TemplateHaskell just:
-- > -- $(makeLenses ''Auth)
-- >
-- > pAuth ∷ MParser Auth
-- > pAuth = id
-- >    <$< user .:: strOption
-- >        × long "user"
-- >        ⊕ short 'u'
-- >        ⊕ help "user name"
-- >    <*< pwd .:: strOption
-- >        × long "pwd"
-- >        ⊕ help "password for user"
--
(.::) ∷ (Alternative φ, Applicative φ) ⇒ Lens' α β → φ β → φ (α → α)
(.::) a opt = set a <$> opt <|> pure id
infixr 5 .::
{-# INLINE (.::) #-}

-- | An operator for applying a setter to an option parser that yields
-- a modification function.
--
-- Example usage:
--
-- > data HttpURL = HttpURL
-- >     { _auth ∷ !Auth
-- >     , _domain ∷ !String
-- >     }
-- >
-- > auth ∷ Functor φ ⇒ (Auth → φ Auth) → HttpURL → φ HttpURL
-- > auth f s = (\u → s { _auth = u }) <$> f (_auth s)
-- >
-- > domain ∷ Functor φ ⇒ (String → φ String) → HttpURL → φ HttpURL
-- > domain f s = (\u → s { _domain = u }) <$> f (_domain s)
-- >
-- > path ∷ Functor φ ⇒ (String → φ String) → HttpURL → φ HttpURL
-- > path f s = (\u → s { _path = u }) <$> f (_path s)
-- >
-- > -- or with lenses and TemplateHaskell just:
-- > -- $(makeLenses ''HttpURL)
-- >
-- > pHttpURL ∷ MParser HttpURL
-- > pHttpURL = id
-- >     <$< auth %:: pAuth
-- >     <*< domain .:: strOption
-- >         × long "domain"
-- >         ⊕ short 'd'
-- >         ⊕ help "HTTP domain"
--
(%::) ∷ (Alternative φ, Applicative φ) ⇒ Lens' α β → φ (β → β) → φ (α → α)
(%::) a opt = over a <$> opt <|> pure id
infixr 5 %::
{-# INLINE (%::) #-}

-- -------------------------------------------------------------------------- --
-- Misc Utilities for Command Line Option Parsing

boolReader
    ∷ (Eq a, Show a, CI.FoldCase a, IsString a, IsString e, Monoid e)
    ⇒ a
    → Either e Bool
boolReader x = case CI.mk x of
    "true" → Right True
    "false" → Right False
    _ → Left $ "failed to read Boolean value " ⊕ fromString (show x)
        ⊕ ". Expected either \"true\" or \"false\""

-- | The 'boolOption' is an alternative to 'O.switch'.
--
-- Using 'O.switch' with command line parsers that overwrite settings
-- from a configuration file is problematic: the absence of the 'switch'
-- is interpreted as setting the respective configuration value to 'False'.
-- So there is no way to specify on the command line that the value from
-- the configuration file shall be used. Some command line UIs use two
-- different options for those values, for instance @--enable-feature@ and
-- @--disable-feature@. This option instead expects a Boolean value. Beside
-- that it behaves like any other option.
--
boolOption
    ∷ O.Mod O.OptionFields Bool
    → O.Parser Bool
boolOption mods = O.option (O.eitherReader boolReader)
    × O.metavar "true|false"
    ⊕ O.completeWith ["true", "false", "TRUE", "FALSE", "True", "False"]
    ⊕ mods

fileOption
    ∷ O.Mod O.OptionFields String
    → O.Parser FilePath
fileOption mods = O.strOption
    × O.metavar "FILE"
    ⊕ O.action "file"
    ⊕ mods

eitherReadP
    ∷ T.Text
    → P.ReadP a
    → T.Text
    → Either T.Text a
eitherReadP label p s =
    case [ x | (x,"") ← P.readP_to_S p (T.unpack s) ] of
        [x] → Right x
        []  → Left $ "eitherReadP: no parse for " ⊕ label ⊕ " of " ⊕ s
        _  → Left $ "eitherReadP: ambigous parse for " ⊕ label ⊕ " of " ⊕ s

