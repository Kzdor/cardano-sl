{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE RankNTypes          #-}

-- | High level workers.

module Pos.Worker
       ( allWorkers
       ) where

import           Universum

import           Pos.Block.Worker (blkWorkers)
import           Pos.Communication (OutSpecs, Relay, relayPropagateOut)
import           Pos.Communication.Util (wrapActionSpec)
import           Pos.Context (NodeContext (..))
import           Pos.Delegation.Listeners (delegationRelays)
import           Pos.Delegation.Worker (dlgWorkers)
import           Pos.Launcher.Resource (NodeResources (..))
import           Pos.Slotting (logNewSlotWorker, slottingWorkers)
import           Pos.Ssc.Listeners (sscRelays)
import           Pos.Ssc.Worker (sscWorkers)
import           Pos.Txp.Network.Listeners (txRelays)
import           Pos.Update.Worker (usWorkers)
import           Pos.Util (mconcatPair)
import           Pos.Util.JsonLog (JLEvent (JLTxReceived))
import           Pos.Util.TimeWarp (jsonLog)
import           Pos.WorkMode (WorkMode)
import           Pos.Worker.Types (WorkerSpec, localWorker)

-- | All, but in reality not all, workers used by full node.
allWorkers
    :: forall ext ctx m .
       WorkMode ctx m
    => NodeResources ext m -> ([WorkerSpec m], OutSpecs)
allWorkers NodeResources {..} = mconcatPair
    [
      -- Only workers of "onNewSlot" type
      -- I have no idea what this ↑ comment means (@gromak).

      wrap' "ssc"        $ sscWorkers
    , wrap' "us"         $ usWorkers

      -- Have custom loggers
    , wrap' "block"      $ blkWorkers ncSubscriptionKeepAliveTimer
    , wrap' "delegation" $ dlgWorkers
    , wrap' "slotting"   $ (properSlottingWorkers, mempty)

      -- MAGIC "relay" out specs.
      -- There's no cardano-sl worker for them; they're put out by the outbound
      -- queue system from time-warp (enqueueConversation on SendActions).
    , ([], relayPropagateOut (mconcat [delegationRelays, sscRelays, txRelays logTx] :: [Relay m]))
    ]
  where
    NodeContext {..} = nrContext
    properSlottingWorkers =
       fst (localWorker logNewSlotWorker) :
       map (fst . localWorker) (slottingWorkers ncSlottingContext)
    wrap' lname = first (map $ wrapActionSpec $ "worker" <> lname)
    logTx = jsonLog . JLTxReceived
