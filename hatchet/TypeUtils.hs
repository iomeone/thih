{-------------------------------------------------------------------------------

        Copyright:              The Hatchet Team (see file Contributors)

        Module:                 TypeUtils

        Description:            Utility functions for manipulating types,
                                and converting between the syntactic
                                representation of types and the internal
                                representation of types.

        Primary Authors:        Bernie Pope

        Notes:                  See the file License for license information

-------------------------------------------------------------------------------}

module TypeUtils (aHsTypeToType,
                  aHsQualTypeToQualType,
                  aHsTypeSigToAssumps,
                  aHsAsstToPred,
                  qualifyAssump,
                  flattenLeftTypeApplication) where

import AnnotatedHsSyn           (AHsType (..),
                                 AHsQualType (..),
                                 AHsIdentifier (..),
                                 AHsName (..),
                                 AModule (AModule),
                                 AHsAsst,
                                 bogusASrcLoc,
                                 AHsDecl (..),
                                 AHsContext) 

import Representation           (Type (..),
                                 Tyvar (..),
                                 Tycon (..),
                                 Kind (..),
                                 Pred (..),
                                 Qual (..), 
                                 Scheme (..),
                                 Assump (..))

import HaskellPrelude           (fn)

import Type                     (tv, 
                                 quantify, 
                                 makeAssump,
                                 assumpScheme,
                                 assumpId)

import Utils                    (fromAHsName,
                                 isQualified)

import KindInference            (KindEnv, 
                                 kiAHsQualType,
                                 kindOf)

-------------------------------------------------------------------------------------------
--
--  The conversion functions:
--
--    aHsTypeToType

--------------------------------------------------------------------------------
    
-- note that the types are generated without generalised type
-- variables, ie there will be no TGens in the output
-- to get the generalised variables a second phase
-- of generalisation must be applied

aHsTypeToType :: KindEnv -> AHsType -> Type

-- arrows

aHsTypeToType kt (AHsTyFun t1 t2)
   = aHsTypeToType kt t1 `fn` aHsTypeToType kt t2

-- tuples

aHsTypeToType kt tuple@(AHsTyTuple types)
   = TTuple $ map (aHsTypeToType kt) types

-- application

aHsTypeToType kt (AHsTyApp t1 t2)
   = TAp (aHsTypeToType kt t1) (aHsTypeToType kt t2)

-- variables, we must know the kind of the variable here!
-- they are assumed to already exist in the kindInfoTable
-- which was generated by the process of KindInference

aHsTypeToType kt (AHsTyVar name)
   = TVar $ Tyvar name (kindOf name kt)

-- type constructors, we must know the kind of the constructor.
-- here we also qualify the type constructor if it is 
-- currently unqualified

aHsTypeToType kt (AHsTyCon name)
   = TCon $ Tycon name (kindOf name kt)

aHsQualTypeToQualType :: KindEnv -> AHsQualType -> Qual Type
aHsQualTypeToQualType kt (AHsQualType cntxt t)
   = map (aHsAsstToPred kt) cntxt :=> aHsTypeToType kt t
aHsQualTypeToQualType kt (AHsUnQualType t)
   = [] :=> aHsTypeToType kt t

-- this version quantifies all the type variables
-- perhaps there should be a version that is 
-- parameterised with which variables to quantify

aHsQualTypeToScheme :: KindEnv -> AHsQualType -> Scheme
aHsQualTypeToScheme kt qualType
   = quantify vars qt
   where
   qt = aHsQualTypeToQualType kt qualType
   vars = tv qt 

-- one sig can be given to multiple names, hence
-- the multiple assumptions in the output

aHsTypeSigToAssumps :: KindEnv -> AHsDecl -> [Assump]
aHsTypeSigToAssumps kt sig@(AHsTypeSig _sloc names qualType)
   = [n :>: scheme | n <- names]
   where
   scheme = aHsQualTypeToScheme newEnv qualType 
   newEnv = kiAHsQualType kt qualType 



aHsAsstToPred :: KindEnv -> AHsAsst -> Pred
aHsAsstToPred kt (className, varName)
   = IsIn className (TVar $ Tyvar varName (kindOf className kt)) 


{-
   converts leftmost type applications into lists

   (((TC v1) v2) v3) => [TC, v1, v2, v3]

-}
flattenLeftTypeApplication :: AHsType -> [AHsType]
flattenLeftTypeApplication t
   = flatTypeAcc t []
   where
   flatTypeAcc (AHsTyApp t1 t2) acc
      = flatTypeAcc t1 (t2:acc)
   flatTypeAcc nonTypApp acc
      = nonTypApp:acc

-- qualifies a type assumption to a given module, unless
-- it is already qualified

qualifyAssump :: AModule -> Assump -> Assump 
qualifyAssump mod assump
   | isQualified ident = assump  -- do nothing 
   | otherwise = makeAssump newAQualIdent scheme
   where
   scheme :: Scheme
   scheme = assumpScheme assump
   ident :: AHsName
   ident = assumpId assump 
   newAQualIdent :: AHsName
   newAQualIdent = AQual mod $ AHsIdent $ fromAHsName ident
