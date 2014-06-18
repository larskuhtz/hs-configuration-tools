-- ------------------------------------------------------ --
-- Copyright © 2014 AlephCloud Systems, Inc.
-- ------------------------------------------------------ --

{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}

module Main
( main
) where

import Configuration.Utils
import Data.Monoid.Unicode
import Prelude.Unicode

-- This assume usage of cabal with custom Setup.hs
--
import PkgInfo_url_example

-- | Specification of the authentication section of a URL.
--
data Auth = Auth
    { _user ∷ !String
    , _pwd ∷ !String
    }

-- Define Lenses.
--
-- (alternatively we could have used TemplateHaskell along with
-- 'makeLenses' from "Control.Lens" from the lens package.)

user ∷ Functor φ ⇒ (String → φ String) → Auth → φ Auth
user f s = (\u → s { _user = u }) <$> f (_user s)

pwd ∷ Functor φ ⇒ (String → φ String) → Auth → φ Auth
pwd f s = (\p → s { _pwd = p }) <$> f (_pwd s)

defaultAuth ∷ Auth
defaultAuth = Auth
    { _user = ""
    , _pwd = ""
    }

instance FromJSON (Auth → Auth) where
    parseJSON = withObject "Auth" $ \o → pure id
        ⊙ user ..: "user" × o
        ⊙ pwd ..: "pwd" × o

instance ToJSON Auth where
    toJSON a = object
        [ "user" .= _user a
        , "pwd" .=  _pwd a
        ]

pAuth ∷ MParser Auth
pAuth = pure id
    ⊙ user .:: strOption
        × long "user"
        ⊕ help "user name"
    ⊙ pwd .:: strOption
        × long "pwd"
        ⊕ help "password for user"

-- | Simplified specification of an HTTP URL
--
data HttpURL = HttpURL
    { _auth ∷ !Auth
    , _domain ∷ !String
    , _path ∷ !String
    }

auth ∷ Functor φ ⇒ (Auth → φ Auth) → HttpURL → φ HttpURL
auth f s = (\u → s { _auth = u }) <$> f (_auth s)

domain ∷ Functor φ ⇒ (String → φ String) → HttpURL → φ HttpURL
domain f s = (\u → s { _domain = u }) <$> f (_domain s)

path ∷ Functor φ ⇒ (String → φ String) → HttpURL → φ HttpURL
path f s = (\u → s { _path = u }) <$> f (_path s)

defaultHttpURL ∷ HttpURL
defaultHttpURL = HttpURL
    { _auth = defaultAuth
    , _domain = ""
    , _path = ""
    }

instance FromJSON (HttpURL → HttpURL) where
    parseJSON = withObject "HttpURL" $ \o → pure id
        ⊙ auth %.: "auth" × o
        ⊙ domain ..: "domain" × o
        ⊙ path ..: "path" × o

instance ToJSON HttpURL where
    toJSON a = object
        [ "auth" .= _auth a
        , "domain" .= _domain a
        , "path" .= _path a
        ]

pHttpURL ∷ MParser HttpURL
pHttpURL = pure id
    ⊙ auth %:: pAuth
    ⊙ domain .:: strOption
        × long "domain"
        ⊕ short 'd'
        ⊕ help "HTTP domain"
    ⊙ path .:: strOption
        × long "path"
        ⊕ short 'p'
        ⊕ help "HTTP URL path"

-- | Information about the main Application
--
mainInfo ∷ ProgramInfo HttpURL
mainInfo = programInfo "HTTP URL" pHttpURL defaultHttpURL

-- This version assumes usage of cabal with custom Setup.hs
--
main ∷ IO ()
main = runWithPkgInfoConfiguration mainInfo pkgInfo $ \conf → do
    putStrLn
        $ "http://"
        ⊕ (_user ∘ _auth) conf
        ⊕ ":"
        ⊕ (_pwd ∘ _auth) conf
        ⊕ "@"
        ⊕ _domain conf
        ⊕ "/"
        ⊕ _path conf

-- This version does not rely on cabal
--
main_ ∷ IO ()
main_ = runWithConfiguration mainInfo $ \conf → do
    putStrLn
        $ "http://"
        ⊕ (_user ∘ _auth) conf
        ⊕ ":"
        ⊕ (_pwd ∘ _auth) conf
        ⊕ "@"
        ⊕ _domain conf
        ⊕ "/"
        ⊕ _path conf
