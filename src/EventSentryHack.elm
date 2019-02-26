module EventSentryHack exposing (EventSentry, Msg(..), init, pollForChanges, update)

import Eth
import Eth.Decode
import Eth.Types exposing (Address)
import Http
import Json.Decode exposing (Decoder)
import Task


type alias EventSentry eventType msg =
    { httpProvider : Eth.Types.HttpProvider
    , contractAddress : Address
    , logFilterMethod : Address -> Eth.Types.LogFilter
    , eventDecoder : Decoder eventType
    , msgConstructor : Result Http.Error (List (Eth.Types.Event eventType)) -> msg
    , nextBlockToScan : Int
    , tagger : Msg -> msg
    }


type Msg
    = NoOp
    | LatestBlocknumFetchResult (Result Http.Error Int)


init :
    Eth.Types.HttpProvider
    -> Address
    -> (Address -> Eth.Types.LogFilter)
    -> Decoder eventType
    -> (Result Http.Error (List (Eth.Types.Event eventType)) -> msg)
    -> Int
    -> (Msg -> msg)
    -> EventSentry eventType msg
init httpProvider contractAddress logFilterMethod eventDecoder msgConstructor startBlock tagger =
    { httpProvider = httpProvider
    , contractAddress = contractAddress
    , logFilterMethod = logFilterMethod
    , eventDecoder = eventDecoder
    , msgConstructor = msgConstructor
    , nextBlockToScan = startBlock
    , tagger = tagger
    }


update : Msg -> EventSentry eventType msg -> ( EventSentry eventType msg, Cmd msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        LatestBlocknumFetchResult result ->
            case result of
                Ok latestBlocknum ->
                    if latestBlocknum >= model.nextBlockToScan then
                        let
                            cmd =
                                fetchEventsCmd
                                    model.httpProvider
                                    model.contractAddress
                                    model.logFilterMethod
                                    ( Eth.Types.BlockNum model.nextBlockToScan, Eth.Types.BlockNum latestBlocknum )
                                    model.eventDecoder
                                    model.msgConstructor

                            newModel =
                                { model | nextBlockToScan = latestBlocknum + 1 }
                        in
                        ( newModel, cmd )

                    else
                        ( model, Cmd.none )

                Err errstr ->
                    let
                        _ =
                            Debug.log "Error fetching blocknum via EventSentryHack" errstr
                    in
                    ( model, Cmd.none )


pollForChanges : EventSentry eventType msg -> Cmd msg
pollForChanges sentry =
    fetchLatestBlockCmd sentry.httpProvider LatestBlocknumFetchResult
        |> Cmd.map sentry.tagger


fetchLatestBlockCmd : Eth.Types.HttpProvider -> (Result Http.Error Int -> Msg) -> Cmd Msg
fetchLatestBlockCmd httpProvider msgConstructor =
    Eth.getBlockNumber httpProvider
        |> Task.attempt msgConstructor


fetchEventsCmd :
    Eth.Types.HttpProvider
    -> Address
    -> (Address -> Eth.Types.LogFilter)
    -> ( Eth.Types.BlockId, Eth.Types.BlockId )
    -> Decoder eventType
    -> (Result Http.Error (List (Eth.Types.Event eventType)) -> msg)
    -> Cmd msg
fetchEventsCmd httpProvider contractAddress lfMaker blockrange eventDecoder msgConstructor =
    let
        logFilter =
            lfMaker contractAddress
                |> withBlockrange blockrange
    in
    Eth.getDecodedLogs
        httpProvider
        logFilter
        (Eth.Decode.event eventDecoder)
        |> Task.attempt msgConstructor


withBlockrange : ( Eth.Types.BlockId, Eth.Types.BlockId ) -> Eth.Types.LogFilter -> Eth.Types.LogFilter
withBlockrange ( fromBlock, toBlock ) lf =
    { lf
        | fromBlock = fromBlock
        , toBlock = toBlock
    }