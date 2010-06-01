{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Database.Persist
    ( -- * High level design
      Column
    , Table   (..)
      -- * Values
    , PersistValue (..)
    , SqlType (..)
    , Persistable (..)
      -- * Type class
    , Persist (..)
    ) where

import Language.Haskell.TH.Syntax
import Data.Time (Day, TimeOfDay, UTCTime)
import Data.ByteString (ByteString)
import qualified Data.ByteString.UTF8 as BSU
import Data.Ratio (denominator, numerator)
import Control.Applicative
import Data.Typeable (Typeable)
import Data.Int (Int64)

-- | name, type
type Column = (String, (String, Bool)) -- is it nullable?

data Table = Table
    { tableName    :: String
    , tableColumns :: [Column]
    , tableUpdates :: [String]
    , tableFilters :: [(String, Bool, Bool, Bool, Bool, Bool, Bool)] -- eq, ne, gt, lt, ge, le
    , tableOrders  :: [(String, Bool, Bool)] -- asc, desc
    , tableUniques :: [(String, [String])]
    }

instance Lift Table where
    lift (Table a b c d e f) = do
        t <- [|Table|]
        a' <- lift a
        b' <- lift b
        c' <- lift c
        d' <- lift d
        e' <- lift e
        f' <- lift f
        return $ t `AppE` a' `AppE` b' `AppE` c' `AppE` d' `AppE` e' `AppE` f'

data PersistValue = PersistString String
                  | PersistByteString ByteString
                  | PersistInteger Integer
                  | PersistInt64 Int64
                  | PersistRational Rational
                  | PersistDouble Double
                  | PersistDay Day
                  | PersistTimeOfDay TimeOfDay
                  | PersistUTCTime UTCTime
                  | PersistNull
    deriving (Show, Read, Eq, Typeable)

data SqlType = SqlString
             | SqlInteger
             | SqlReal
             | SqlDay
             | SqlTime
             | SqlDayTime
             | SqlBlob

class Persistable a where
    toPersistValue :: a -> PersistValue
    fromPersistValue :: PersistValue -> Either String a
    sqlType :: a -> SqlType
    isNullable :: a -> Bool
    isNullable _ = False

instance Persistable String where
    toPersistValue = PersistString
    fromPersistValue (PersistString s) = Right s
    fromPersistValue (PersistByteString bs) = Right $ BSU.toString bs
    fromPersistValue (PersistInteger i) = Right $ show i
    fromPersistValue (PersistInt64 i) = Right $ show i
    fromPersistValue (PersistRational r)
        | denominator r == 1 = Right $ show $ numerator r
        | otherwise = Right $ show $ (fromRational r :: Double)
    fromPersistValue (PersistDouble d) = Right $ show d
    fromPersistValue (PersistDay d) = Right $ show d
    fromPersistValue (PersistTimeOfDay d) = Right $ show d
    fromPersistValue (PersistUTCTime d) = Right $ show d
    fromPersistValue PersistNull = Left "Unexpected null"
    sqlType _ = SqlString

instance Persistable ByteString where
    toPersistValue = PersistByteString
    fromPersistValue (PersistByteString bs) = Right bs
    fromPersistValue x = BSU.fromString <$> fromPersistValue x
    sqlType _ = SqlBlob

instance Persistable Integer where
    toPersistValue = PersistInteger
    fromPersistValue (PersistInteger i) = Right i
    fromPersistValue (PersistInt64 i) = Right $ fromIntegral i
    fromPersistValue x = Left $ "Expected Integer, received: " ++ show x
    sqlType _ = SqlInteger

instance Persistable Int where
    toPersistValue = PersistInteger . fromIntegral
    fromPersistValue (PersistInteger i) = Right $ fromInteger i
    fromPersistValue (PersistInt64 i) = Right $ fromIntegral i
    fromPersistValue x = Left $ "Expected Integer, received: " ++ show x
    sqlType _ = SqlInteger

instance Persistable a => Persistable (Maybe a) where
    toPersistValue Nothing = PersistNull
    toPersistValue (Just a) = toPersistValue a
    fromPersistValue PersistNull = Right Nothing
    fromPersistValue x = fmap Just $ fromPersistValue x
    sqlType _ = sqlType (undefined :: a)
    isNullable _ = True

class Monad m => Persist val m where
    data Key    val
    data Update val
    data Filter val
    data Order  val
    data Unique val

    -- initialization, value is ignored
    initialize  :: val                          -> m ()

    -- insert
    insert      :: val                          -> m (Key val)
    insertR     :: val                          -> m (Key val)
    replace     :: Key val      -> val          -> m ()

    -- modify
    update      :: Key val      -> [Update val] -> m ()
    updateWhere :: [Filter val] -> [Update val] -> m ()

    -- delete
    delete      :: Key val                      -> m ()
    deleteBy    :: Unique val                   -> m ()
    deleteWhere :: [Filter val]                 -> m ()

    -- read single
    get         :: Key val                      -> m (Maybe val)
    getBy       :: Unique val                   -> m (Maybe (Key val, val))

    -- read multiple
    select      :: [Filter val] -> [Order val]  -> m [(Key val, val)]
