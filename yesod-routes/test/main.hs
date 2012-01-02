{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
import Test.Hspec.Monadic
import Test.Hspec.HUnit ()
import Test.HUnit ((@?=))
import Data.Text (Text, unpack)
import Yesod.Routes.Dispatch hiding (Static, Dynamic)
import Yesod.Routes.Class hiding (Route)
import qualified Yesod.Routes.Class as YRC
import qualified Yesod.Routes.Dispatch as D
import Yesod.Routes.TH hiding (Dispatch)
import Language.Haskell.TH.Syntax
import qualified Data.Map as Map

result :: ([Text] -> Maybe Int) -> Dispatch Int
result f ts = f ts

justRoot :: Dispatch Int
justRoot = toDispatch
    [ Route [] False $ result $ const $ Just 1
    ]

twoStatics :: Dispatch Int
twoStatics = toDispatch
    [ Route [D.Static "foo"] False $ result $ const $ Just 2
    , Route [D.Static "bar"] False $ result $ const $ Just 3
    ]

multi :: Dispatch Int
multi = toDispatch
    [ Route [D.Static "foo"] False $ result $ const $ Just 4
    , Route [D.Static "bar"] True $ result $ const $ Just 5
    ]

dynamic :: Dispatch Int
dynamic = toDispatch
    [ Route [D.Static "foo"] False $ result $ const $ Just 6
    , Route [D.Dynamic] False $ result $ \ts ->
        case ts of
            [t] ->
                case reads $ unpack t of
                    [] -> Nothing
                    (i, _):_ -> Just i
            _ -> error $ "Called dynamic with: " ++ show ts
    ]

overlap :: Dispatch Int
overlap = toDispatch
    [ Route [D.Static "foo"] False $ result $ const $ Just 20
    , Route [D.Static "foo"] True $ result $ const $ Just 21
    , Route [] True $ result $ const $ Just 22
    ]

test :: Dispatch Int -> [Text] -> Maybe Int
test dispatch ts = dispatch ts

data MyApp = MyApp

data MySub = MySub
instance RenderRoute MySub where
    data YRC.Route MySub = MySubRoute ([Text], [(Text, Text)])
        deriving (Show, Eq, Read)
    renderRoute (MySubRoute x) = x

do
    texts <- [t|[Text]|]
    let ress =
            [ Resource "RootR" [] $ Methods Nothing ["GET"]
            , Resource "BlogPostR" [Static "blog", Dynamic $ ConT ''Text] $ Methods Nothing ["GET"]
            , Resource "WikiR" [Static "wiki"] $ Methods (Just texts) []
            , Resource "SubsiteR" [Static "subsite"] $ Subsite (ConT ''MySub) "getMySub"
            ]
    rrinst <- mkRenderRouteInstance (ConT ''MyApp) ress
    dispatch <- mkDispatchClause ress
    return
        [ rrinst
        , FunD (mkName "thDispatch") [dispatch]
        ]

type RunHandler handler master sub app =
        handler
     -> master
     -> sub
     -> YRC.Route sub
     -> (YRC.Route sub -> YRC.Route master)
     -> app

thDispatchAlias
    :: (master ~ MyApp, handler ~ String)
    => master
    -> sub
    -> (YRC.Route sub -> YRC.Route master)
    -> RunHandler handler master sub app
    -> app
    -> [Text]
    -> app
thDispatchAlias = thDispatch

runHandler :: RunHandler String MyApp sub (String, Maybe (YRC.Route MyApp))
runHandler h _ _ subRoute toMaster = (h, Just $ toMaster subRoute)

main :: IO ()
main = hspecX $ do
    describe "justRoot" $ do
        it "dispatches correctly" $ test justRoot [] @?= Just 1
        it "fails correctly" $ test justRoot ["foo"] @?= Nothing
    describe "twoStatics" $ do
        it "dispatches correctly to foo" $ test twoStatics ["foo"] @?= Just 2
        it "dispatches correctly to bar" $ test twoStatics ["bar"] @?= Just 3
        it "fails correctly (1)" $ test twoStatics [] @?= Nothing
        it "fails correctly (2)" $ test twoStatics ["bar", "baz"] @?= Nothing
    describe "multi" $ do
        it "dispatches correctly to foo" $ test multi ["foo"] @?= Just 4
        it "dispatches correctly to bar" $ test multi ["bar"] @?= Just 5
        it "dispatches correctly to bar/baz" $ test multi ["bar", "baz"] @?= Just 5
        it "fails correctly (1)" $ test multi [] @?= Nothing
        it "fails correctly (2)" $ test multi ["foo", "baz"] @?= Nothing
    describe "dynamic" $ do
        it "dispatches correctly to foo" $ test dynamic ["foo"] @?= Just 6
        it "dispatches correctly to 7" $ test dynamic ["7"] @?= Just 7
        it "dispatches correctly to 42" $ test dynamic ["42"] @?= Just 42
        it "fails correctly on five" $ test dynamic ["five"] @?= Nothing
        it "fails correctly on too many" $ test dynamic ["foo", "baz"] @?= Nothing
        it "fails correctly on too few" $ test dynamic [] @?= Nothing
    describe "overlap" $ do
        it "dispatches correctly to foo" $ test overlap ["foo"] @?= Just 20
        it "dispatches correctly to foo/bar" $ test overlap ["foo", "bar"] @?= Just 21
        it "dispatches correctly to bar" $ test overlap ["bar"] @?= Just 22
        it "dispatches correctly to []" $ test overlap [] @?= Just 22

    describe "RenderRoute instance" $ do
        it "renders root correctly" $ renderRoute RootR @?= ([], [])
        it "renders blog post correctly" $ renderRoute (BlogPostR "foo") @?= (["blog", "foo"], [])
        it "renders wiki correctly" $ renderRoute (WikiR ["foo", "bar"]) @?= (["wiki", "foo", "bar"], [])
        it "renders subsite correctly" $ renderRoute (SubsiteR $ MySubRoute (["foo", "bar"], [("baz", "bin")]))
            @?= (["subsite", "foo", "bar"], [("baz", "bin")])

    describe "thDispatch" $ do
        let disp = thDispatchAlias MyApp MyApp id runHandler ("404", Nothing)
        it "routes to root" $ disp [] @?= ("this is the root", Just RootR)
        it "routes to blog post" $ disp ["blog", "somepost"]
            @?= ("some blog post: somepost", Just $ BlogPostR "somepost")

getRootR :: String
getRootR = "this is the root"

{- FIXME
getBlogPostR :: Text -> String
getBlogPostR t = "some blog post: " ++ unpack t
-}
getBlogPostR = undefined

handleWikiR = "the wiki"

handleSubsiteR = "a subsite"
