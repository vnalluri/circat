{-# LANGUAGE TypeOperators, TypeFamilies, ConstraintKinds, GADTs #-}
{-# LANGUAGE Rank2Types, MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances, FlexibleContexts #-}
{-# LANGUAGE UndecidableInstances #-} -- see below

{-# OPTIONS_GHC -Wall #-}

-- {-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP
-- {-# OPTIONS_GHC -fno-warn-unused-binds   #-} -- TEMP

----------------------------------------------------------------------
-- |
-- Module      :  Circat.Classes
-- Copyright   :  (c) 2013 Tabula, Inc.
-- License     :  BSD3
-- 
-- Maintainer  :  conal@tabula.com
-- Stability   :  experimental
-- 
-- Additional type classes for circuit-friendly operations
----------------------------------------------------------------------

module Circat.Classes where

-- TODO: explicit exports

import Prelude hiding (id,(.),const,not,and,or,fst,snd)
import qualified Prelude as P
import Control.Arrow (arr,Kleisli)

import GHC.Prim (Constraint)

import TypeUnary.Vec (Vec(..),Z,S,Nat(..),IsNat(..))

import Circat.Misc ((:*),(<~))
import Circat.Category -- (Category(..),ProductCat(..),inRassocP,UnitCat(..))
import Circat.Pair
import Circat.State -- (StateCat(..),pureState,StateFun)

-- | Category with boolean operations.
class ProductCat k => BoolCat k where
  type BoolT k
  not :: b ~ BoolT k => b `k` b
  and, or, xor :: b ~ BoolT k => (b :* b) `k` b

type BoolWith k b = (BoolCat k, b ~ BoolT k)

-- The Category superclass is just for convenience.

instance BoolCat (->) where
  type BoolT (->) = Bool
  not = P.not
  and = P.uncurry (&&)
  or  = P.uncurry (||)
  xor = P.uncurry (/=)

class BoolCat k => EqCat k where
  type EqKon k a :: Constraint
  type EqKon k a = Yes a
  eq, neq :: (Eq a, EqKon k a, b ~ BoolT k) => (a :* a) `k` b
  neq = not . eq

-- TODO: Revisit the type constraints for EqCat.

instance EqCat (->) where
  type EqKon (->) a = Yes a
  eq  = P.uncurry (==)
  neq = P.uncurry (/=)

class (UnitCat k, ProductCat k) => VecCat k where
  toVecZ :: () `k` Vec Z a
  unVecZ :: Vec Z a `k` ()
  toVecS :: (a :* Vec n a) `k` Vec (S n) a
  unVecS :: Vec (S n) a `k` (a :* Vec n a)

reVecZ :: VecCat k => Vec Z a `k` Vec Z b
reVecZ = toVecZ . unVecZ

inVecS :: VecCat k =>
          ((a :* Vec m a) `k` (b :* Vec n b))
       -> (Vec  (S m)  a `k` Vec  (S n)   b)
inVecS = toVecS <~ unVecS

instance VecCat (->) where
  toVecZ ()        = ZVec
  unVecZ ZVec      = ()
  toVecS (a,as)    = a :< as
  unVecS (a :< as) = (a,as)

instance Monad m => VecCat (Kleisli m) where
  toVecZ = arr toVecZ
  unVecZ = arr unVecZ
  toVecS = arr toVecS
  unVecS = arr unVecS

instance VecCat k => VecCat (StateFun k s) where
  toVecZ = pureState toVecZ
  unVecZ = pureState unVecZ
  toVecS = pureState toVecS
  unVecS = pureState unVecS

instance (ClosedCatWith k s, VecCat k) => VecCat (StateExp k s) where
  toVecZ = pureState toVecZ
  unVecZ = pureState unVecZ
  toVecS = pureState toVecS
  unVecS = pureState unVecS

class (PairCat k, BoolCat k) => AddCat k where
  -- | Half adder: addends in; sum and carry out. Default via logic.
  halfAdd :: b ~ BoolT k =>
             (b :* b) `k` (b :* b)
  halfAdd = xor &&& and
  -- | Full adder: carry and addend pairs in; sum and carry out.
  -- Default via 'halfAdd'.
  fullAdd :: b ~ BoolT k =>
             (b :* Pair b) `k` (b :* b)
  fullAdd = second or . inLassocP (first halfAdd) . second (halfAdd . unPair)

{-

second (halfAdd.unPair) :: C * A       -> C * (C * S)
lassocP                 :: C * (S * C) -> (C * S) * C
first halfAdd           :: (C * S) * C -> (S * C) * C
rassocP                 :: (S * C) * C -> S * (C * C)
second or               :: S * (C * C) -> S * C

-}

instance AddCat (->)  -- use defaults

-- Structure addition with carry in & out

type Adds k f = 
  (BoolT k :* f (Pair (BoolT k))) `k` (f (BoolT k) :* BoolT k)

class AddCat k => AddsCat k f where
  adds :: Adds k f

type AddK k = (ConstUCat k (Vec Z (BoolT k)), AddCat k, VecCat k)

instance (AddK k, IsNat n) => AddsCat k (Vec n) where
  adds = addVN nat

-- Illegal irreducible constraint ConstKon k () in superclass/instance head
-- context (Use -XUndecidableInstances to permit this)

type AddVP n = forall k. AddK k => Adds k (Vec n)

addVN :: Nat n -> AddVP n
addVN Zero     = lconst ZVec . fst

addVN (Succ n) = first toVecS . lassocP . second (addVN n)
               . rassocP . first fullAdd . lassocP
               . second unVecS

{- Derivation:

-- C carry, A addend pair, R result

second unVecS    :: C :* As (S n) `k` C :* (A :* As n)
lassocP          ::               `k` (C :* A) :* As n
first fullAdd    ::               `k` (S :* C) :* As n
rassocP          ::               `k` S :* (C :* As n)
second (addVN n) ::               `k` S :* (Rs n :* C)
lassocP          ::               `k` (S :* Rs n) :* C
first toVecS     ::               `k` Rs (S n) :* C

-}

-- TODO: Do I really need CTraversableKon, or can I make k into an argument?
-- Try, and rename "CTraversable" to "TraversableCat". The Kon becomes superclass constraints.

class CTraversable t where
  type CTraversableKon t k :: Constraint
  type CTraversableKon t k = () ~ () -- or just (), if it works
  traverseC :: CTraversableKon t k => (a `k` b) -> (t a `k` t b)

type CTraversableWith t k = (CTraversable t, CTraversableKon t k)

instance CTraversable (Vec Z) where
  type CTraversableKon (Vec Z) k = VecCat k
  traverseC _ = reVecZ

instance CTraversable (Vec n) => CTraversable (Vec (S n)) where
  type CTraversableKon (Vec (S n)) k =
    (VecCat k, CTraversableKon (Vec n) k)
  traverseC f = inVecS (f *** traverseC f)

instance CTraversable Pair where
  type CTraversableKon Pair k = PairCat k
  traverseC f = inPair (f *** f)

-- TODO: Maybe move Vec support to a new Vec module, alongside the RTree module.

traverseCurry :: 
  ( ConstUCat k (t b), CTraversableWith t k, StrongCat k t
  , StrongKon k t a b ) =>
  t b -> ((a :* b) `k` c) -> (a `k` t c)
traverseCurry q h = traverseC h . lstrength . rconst q

{- Derivation:

q :: t b
h :: a :* b :> c

rconst q    :: a          `k` (a :* t b)
lstrength   :: a :* t b   `k` t (a :* b)
traverseC h :: t (a :* b) `k` t c

traverse h . lstrength . rconst idTrie :: a `k` t c

-}

-- Special case. To remove.

-- trieCurry :: ( HasTrie b, StrongCat k (Trie b)
--              , CTraversableWith (Trie b) k
--              , UnitCat k, ConstUCat k (b :->: b) ) =>
--              ((a :* b) `k` c) -> (a `k` (b :->: c))
-- trieCurry = traverseCurry idTrie

-- TODO: Move CTraversable and trieCurry to Category.


{--------------------------------------------------------------------
    Addition via state and traversal
--------------------------------------------------------------------}

type AddState sk =
  (StateCat sk, StateKon sk, StateT sk ~ BoolT (StateBase sk), AddCat (StateBase sk))

-- Simpler but exposes k:
-- 
--   type AddState sk k b =
--     (StateCatWith sk k b, AddCat k, b ~ Bool)

-- | Full adder with 'StateCat' interface
fullAddS :: AddState sk => b ~ BoolT (StateBase sk) =>
                              Pair b `sk` b
fullAddS = state fullAdd

-- | Structure adder with 'StateCat' interface
addS :: (AddState sk, CTraversableWith f sk, b ~ BoolT (StateBase sk)) =>
        f (Pair b) `sk` f b
addS = traverseC fullAddS

-- TODO: Rewrite halfAdd & fullAdd via StateCat. Hopefully much simpler.
