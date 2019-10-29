module Routing exposing (Route(..), routeToString, urlToRoute)

import BigInt exposing (BigInt)
import CommonTypes exposing (..)
import Contracts.Types as CTypes
import Eth.Types exposing (Address)
import Eth.Utils
import Url exposing (Url)
import Url.Builder
import Url.Parser exposing ((</>), (<?>), Parser)


type Route
    = InitialBlank
    | CreateCrypto
    | CreateFiat
    | Redeploy TradeReference
    | Trade TradeReference
    | Marketplace
    | AgentHistory Address
    | NotFound


routeParser : Parser (Route -> a) a
routeParser =
    Url.Parser.s "DAIHard"
        </> Url.Parser.oneOf
                [ Url.Parser.map CreateFiat Url.Parser.top
                , Url.Parser.map CreateCrypto (Url.Parser.s "create" </> Url.Parser.s "crypto")
                , Url.Parser.map Redeploy (Url.Parser.s "redeploy" </> tradeRefParser)
                , Url.Parser.map Trade (Url.Parser.s "trade" </> tradeRefParser)
                , Url.Parser.map Marketplace (Url.Parser.s "marketplace")
                , Url.Parser.map AgentHistory (Url.Parser.s "history" </> addressParser)
                , Url.Parser.map (\address -> AgentHistory address) (Url.Parser.s "history" </> addressParser)
                ]


routeToString : Route -> String
routeToString route =
    case route of
        InitialBlank ->
            Url.Builder.absolute [ "DAIHard" ] []

        CreateCrypto ->
            Url.Builder.absolute [ "DAIHard", "create", "crypto" ] []

        CreateFiat ->
            Url.Builder.absolute [ "DAIHard" ] []

        Redeploy tradeRef ->
            Url.Builder.absolute [ "DAIHard", "redeploy", factoryToString tradeRef.factory, String.fromInt tradeRef.id ] []

        Trade tradeRef ->
            Url.Builder.absolute [ "DAIHard", "trade", factoryToString tradeRef.factory, String.fromInt tradeRef.id ] []

        Marketplace ->
            Url.Builder.absolute [ "DAIHard", "marketplace" ] []

        AgentHistory address ->
            Url.Builder.absolute [ "DAIHard", "history", Eth.Utils.addressToString address ] []

        NotFound ->
            Url.Builder.absolute [] []


addressParser : Parser (Address -> a) a
addressParser =
    Url.Parser.custom
        "ADDRESS"
        (Eth.Utils.toAddress >> Result.toMaybe)


tradeRefParser : Parser (TradeReference -> a) a
tradeRefParser =
    Url.Parser.map
        TradeReference
        (factoryParser </> Url.Parser.int)


factoryParser : Parser (FactoryType -> a) a
factoryParser =
    Url.Parser.custom
        "FACTORY"
        (\s ->
            case s of
                "eth" ->
                    Just <| Native Eth

                "keth" ->
                    Just <| Native Kovan

                "dai" ->
                    Just <| Token EthDai

                "kdai" ->
                    Just <| Token KovanDai

                "xdai" ->
                    Just <| Native XDai

                _ ->
                    Nothing
        )


factoryToString : FactoryType -> String
factoryToString factory =
    case factory of
        Native Eth ->
            "eth"

        Native Kovan ->
            "(k)eth"

        Token EthDai ->
            "dai"

        Token KovanDai ->
            "(k)dai"

        Native XDai ->
            "xdai"


buyerOrSellerParser : Parser (BuyerOrSeller -> a) a
buyerOrSellerParser =
    Url.Parser.custom
        "BUYERORSELLER"
        (\s ->
            case s of
                "buyer" ->
                    Just Buyer

                "seller" ->
                    Just Seller

                _ ->
                    Nothing
        )


buyerOrSellerToString : BuyerOrSeller -> String
buyerOrSellerToString buyerOrSeller =
    case buyerOrSeller of
        Buyer ->
            "buyer"

        Seller ->
            "seller"


urlToRoute : Url -> Route
urlToRoute url =
    Maybe.withDefault NotFound (Url.Parser.parse routeParser url)
