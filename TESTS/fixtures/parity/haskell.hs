-- | Parity fixture — Haskell.
--
-- One exported function, one unexported helper, an import, a call,
-- a module constant and a marker.
module Parity.Widget (widen) where

import Parity.Other (bump)

-- | How many.
maxCount :: Int
maxCount = 10

-- | Double a value.
double :: Int -> Int
double n = n * 2

-- | Widen a value.
-- TODO: cap at maxCount
widen :: Int -> Int
widen n = double n + bump maxCount
