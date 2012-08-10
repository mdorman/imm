{-# LANGUAGE NoMonomorphismRestriction, RankNTypes, FlexibleContexts #-}
module Imm.Util where

-- {{{ Imports
import Imm.Types

import qualified Control.Exception as E
import Control.Monad.Error
--import Control.Monad.IO.Class

import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import Data.Functor
import Data.Maybe
import Data.Text.ICU.Convert
import Data.Text.Lazy.Encoding hiding(decodeUtf8)
import qualified Data.Text.Lazy as TL
import Data.Time as T
import Data.Time.RFC2822
import Data.Time.RFC3339

import Network.URI as N

import System.Console.CmdArgs
import System.FilePath
import System.IO
import System.Locale
import System.Timeout as S
-- }}}


-- | Like '(</>)' with first argument in IO to build platform-dependent paths.
(>/>) :: (MonadIO m) => IO FilePath -> FilePath -> m FilePath
(>/>) a b = io $ (</> b) <$> a

-- {{{ Monadic utilities
-- | Shortcut to 'liftIO'
io :: MonadIO m => IO a -> m a
io = liftIO

-- | Monad-agnostic version of 'Control.Exception.try'
try :: (MonadIO m, MonadError ImmError m) => IO a -> m a
try = (io . E.try) >=> either (throwError . IOE) return 

-- | Monad-agnostic version of 'System.timeout'
timeout :: (MonadIO m, MonadError ImmError m) => Int -> IO a -> m a
timeout n f = maybe (throwError TimeOut) (io . return) =<< (io $ S.timeout n (io f))
-- }}}

-- | Print logs with arbitrary importance
logError, logNormal, logVerbose :: MonadIO m => String -> m ()
logError   = io . hPutStr stderr
logNormal  = io . whenNormal . putStrLn
logVerbose = io . whenLoud . putStrLn


-- {{{ Monad-agnostic version of various error-prone functions
-- | Monad-agnostic version of Data.Text.Encoding.decodeUtf8
decodeUtf8 :: MonadError ImmError m => BL.ByteString -> m TL.Text
decodeUtf8 = either (throwError . UnicodeError) return . decodeUtf8'

-- | Monad-agnostic version of 'Network.URI.parseURI'
parseURI :: (MonadError ImmError m) => String -> m URI
parseURI uri = maybe (throwError $ ParseUriError uri) return $ N.parseURI uri

-- | Monad-agnostic version of 'Data.Time.Format.parseTime'
parseTime :: (MonadError ImmError m) => String -> m UTCTime
parseTime string = maybe (throwError $ ParseTimeError string) return $ T.parseTime defaultTimeLocale "%c" string
-- }}}

decode :: (MonadIO m, MonadError ImmError m) => BL.ByteString -> m TL.Text
decode raw = catchError (decodeUtf8 raw) $ return $ do
    conv <- io $ open "ISO-8859-1" Nothing
    return . TL.fromChunks . (\a -> [a]) . toUnicode conv . B.concat . BL.toChunks $ raw

parseDate :: String -> Maybe UTCTime
parseDate date = listToMaybe . map T.zonedTimeToUTC . catMaybes . flip map [readRFC2822, readRFC3339, T.parseTime defaultTimeLocale "%a, %d %b %G %T", T.parseTime defaultTimeLocale "%Y-%m-%d", T.parseTime defaultTimeLocale "%e %b %Y", T.parseTime defaultTimeLocale "%a, %e %b %Y %k:%M:%S %z", T.parseTime defaultTimeLocale "%a, %e %b %Y %T %Z"] $ \f -> f . TL.unpack . TL.strip . TL.pack $ date
