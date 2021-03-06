{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Implementation of "Imm.Hooks" that writes a file for each new RSS/Atom item.
module Imm.Hooks.WriteFile where

-- {{{ Imports
import           Imm.Feed
import           Imm.Hooks
import           Imm.Prelude
import           Imm.Pretty

import           Control.Arrow
import           Control.Monad.Trans.Reader
import           Data.ByteString.Builder
import           Data.ByteString.Streaming     (toStreamingByteString)
import           Data.Monoid.Textual           hiding (elem, map)
import           Data.Time
import           Streaming.With
import           System.Directory              (createDirectoryIfMissing)
import           System.FilePath
import           Text.Atom.Types
import           Text.Blaze.Html.Renderer.Utf8
import           Text.Blaze.Html5              (Html, docTypeHtml,
                                                preEscapedToHtml, (!))
import qualified Text.Blaze.Html5              as H
import           Text.Blaze.Html5.Attributes   as H (charset, href)
import           Text.RSS.Types
import           URI.ByteString
-- }}}

-- * Types

-- | Where and what to write in a file
data FileInfo = FileInfo FilePath Builder

newtype WriteFileSettings = WriteFileSettings (Feed -> FeedElement -> FileInfo)

instance MonadImm (ReaderT WriteFileSettings IO) where
  processNewElement feed element = do
    WriteFileSettings f <- ask
    let FileInfo path content = f feed element
    lift $ createDirectoryIfMissing True $ takeDirectory path
    writeBinaryFile path $ toStreamingByteString content

-- * Default behavior

-- | Wrapper around 'defaultFilePath' and 'defaultFileContent'
defaultSettings :: FilePath            -- ^ Root directory for 'defaultFilePath'
                -> WriteFileSettings
defaultSettings root = WriteFileSettings $ \feed element -> FileInfo
  (defaultFilePath root feed element)
  (defaultFileContent feed element)

-- | Generate a path @<root>/<feed title>/<element date>-<element title>.html@, where @<root>@ is the first argument
defaultFilePath :: FilePath -> Feed -> FeedElement -> FilePath
defaultFilePath root feed element = makeValid $ root </> title </> fileName <.> "html" where
  date = maybe "" (formatTime defaultTimeLocale "%F-") $ getDate element
  fileName = date <> sanitize (convertText $ getTitle element)
  title = sanitize $ convertText $ getFeedTitle feed
  sanitize = replaceIf isPathSeparator '-' >>> replaceAny ".?!#" '_'
  replaceAny :: String -> Char -> String -> String
  replaceAny list = replaceIf (`elem` list)
  replaceIf f b = map (\c -> if f c then b else c)

-- | Generate an HTML page, with a title, a header and an article that contains the feed element
defaultFileContent :: Feed -> FeedElement -> Builder
defaultFileContent feed element = renderHtmlBuilder $ docTypeHtml $ do
  H.head $ do
    H.meta ! H.charset "utf-8"
    H.title $ convertText $ getFeedTitle feed <> " | " <> getTitle element
  H.body $ do
    H.h1 $ convertText $ getFeedTitle feed
    H.article $ do
      H.header $ do
        defaultArticleTitle feed element
        defaultArticleAuthor feed element
        defaultArticleDate feed element
      defaultBody feed element


-- * Low-level helpers

defaultArticleTitle :: Feed -> FeedElement -> Html
defaultArticleTitle _ element@(RssElement item) = H.h2 $ maybe id (\uri -> H.a ! H.href uri) link $ convertText $ getTitle element where
  link = withRssURI (convertDoc . prettyURI) <$> itemLink item
defaultArticleTitle _ element@(AtomElement _) = H.h2 $ convertText $ getTitle element

defaultArticleAuthor :: Feed -> FeedElement -> Html
defaultArticleAuthor _ (RssElement item) = unless (null author) $ H.address $ "Published by " >> convertText author where
  author = itemAuthor item
defaultArticleAuthor _ (AtomElement entry) = H.address $ do
  "Published by "
  forM_ (entryAuthors entry) $ \author -> do
    convertDoc $ prettyPerson author
    ", "

defaultArticleDate :: Feed -> FeedElement -> Html
defaultArticleDate _ element = forM_ (getDate element) $ \date -> H.p $ " on " >> H.time (convertDoc $ prettyTime date)


-- | Generate the HTML content for a given feed element
defaultBody :: Feed -> FeedElement -> Html
defaultBody _ element@(RssElement _) = H.p $ preEscapedToHtml $ getContent element
defaultBody _ element@(AtomElement entry) = do
  unless (null links) $ H.p $ do
    "Related links:"
    H.ul $ forM_ links $ \uri -> H.li (H.a ! H.href (convertAtomURI uri) $ convertAtomURI uri)
  H.p $ preEscapedToHtml $ getContent element
  where links   = map linkHref $ entryLinks entry


convertAtomURI :: (IsString t) => AtomURI -> t
convertAtomURI = withAtomURI convertURI

convertURI :: (IsString t) => URIRef a -> t
convertURI = convertText . decodeUtf8 . serializeURIRef'

convertText :: (IsString t) => Text -> t
convertText = fromString . toString (const "?")

convertDoc :: (IsString t) => Doc a -> t
convertDoc = show
