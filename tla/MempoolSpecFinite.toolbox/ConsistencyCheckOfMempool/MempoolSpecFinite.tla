--------------------- MODULE MempoolSpecFinite ------------------------------

(*
This is a finite version of the "MempoolSpec". 
*)

EXTENDS FiniteSets, Integers, Functions, TLC

\* CONSTANT N

\* ASSUMPTION PositiveIntegerN == N \in Nat /\ N > 0

\* NN == 1..N 

-----------------------------------------------------------------------------

(***************************************************************************)
(*                               ON QUORUMS                                *)
(***************************************************************************)

(***************************************************************************)
(* We make the usual assumption about Byzantine failures.  That is,        *)
(* preparing for the setting of a partially synchronous network, we have   *)
(*                                                                         *)
(* - a fixed number of nodes                                               *)
(*                                                                         *)
(* - less than one third of which exhibit Byzantine behaviour.             *)
(*                                                                         *)
(* In the typical setting of N = 3f+1 validators,                          *)
(*                                                                         *)
(* - a "quorum" is any set that contains more than two thirds of all       *)
(*   nodes;                                                                *)
(*                                                                         *)
(* - a "weak quorum" is a set of nodes whose intersection with any quorum  *)
(*   is non-empty.                                                         *)
(*                                                                         *)
(* In prose, _validator_ means (possibly Byzantine) validator.             *)
(***************************************************************************)

\* Following Lamport's formalization of 
\* `^\href{https://tinyurl.com/2dyuzs6y}{Paxos}^' and 
\* `^\href{https://tinyurl.com/7punrbs2}{Byzantine Paxos,}^'
\* we consider a more general formalization that
\* even could take care of infinite sets.

CONSTANTS Validator,     \* The set of correct (aka good) validators.
          FakeValidator \* The set of possibly faulty (aka bad) validators.
          \* ByzQuorum,
            (***************************************************************)
            (* A Byzantine quorum is set of validators that includes a     *)
            (* quorum of good ones.  In the case that there are 2f+1 good  *)
            (* validators and f bad ones, any set that contains at least   *)
            (* 2f+1 validators is a Byzantine quorum.                      *)
            (***************************************************************)
          \* WeakQuorum
            (***************************************************************)
            (* A weak quorum is a set of validators that includes at least *)
            (* one good one.  If there are f bad validators, then any set  *)
            (* that contaions f+1 validators is a weak quorum.             *)
            (***************************************************************)

(***************************************************************************)
(*  ByzValidator is the (disjoint) union of real or fake validators        *)
(*  (cf. BQA below.)                                                       *)
(***************************************************************************)
ByzValidator == Validator \cup FakeValidator 

TheF == Cardinality(FakeValidator)


ByzQuorum == 
  { X \in  SUBSET ByzValidator : Cardinality(X) > 2 * TheF }
  
WeakQuorum == 
  { X \in  SUBSET ByzValidator : Cardinality(X) > TheF }
  
  
(***************************************************************************)
(* The following assumptions about validators and quorums are used         *)
(* by Lamport in the  safety proof.                                        *)
(***************************************************************************)
ASSUME BQA ==
  \* A validator in ByzValidator is either good or bad.
  /\ Validator \cap FakeValidator = {}                                     
  \* A qourum is a set of (possibly bad) validators.
  /\ \A Q \in ByzQuorum : Q \subseteq ByzValidator                       
  \* Any two quorums have a good validator in common.
  /\ \A Q1, Q2 \in ByzQuorum : Q1 \cap Q2 \cap Validator # {}            
  \* A weak quorum is a set of validators with at least one good validator.
  /\ \A W \in WeakQuorum : /\ W \subseteq ByzValidator                   
                           /\ W \cap Validator # {}                  

(***************************************************************************)
(* Inspired by Lamport's assumption for liveness, we assume BQLA.          *)
(***************************************************************************)
ASSUME BQLA ==
  \* There is a quorum consisting of good validators only.
  /\ \E Q \in ByzQuorum : Q \subseteq Validator
  \* There is a weak quorum consisting of good validators only.
  /\ \E W \in WeakQuorum : W \subseteq Validator


\* end of "ON QUORUMS"

-----------------------------------------------------------------------------

(***************************************************************************)
(*                    WORKER-PRIMARY DISTINCTION                           *)
(***************************************************************************)

(***************************************************************************)
(* One idea of Narwhal and Tusk [N&T] is explicit parallelism via a number *)
(* of workers at each validator.  Each worker of a (correct) validator     *)
(* will have a "mirror" worker at every other validator.                   *)
(*                                                                         *)
(* We use a public parameter, typically a finite set, which serves to      *)
(* index workers such that mirror workers share the same index.  There is  *)
(* no point of using invalid indices by bad validators as these would be   *)
(* ignored.                                                                *)
(***************************************************************************)

\* 'WorkerIndex' is a publicy known finite set of indices. 
CONSTANT WorkerIndex

\* A finite non-empty set of indices (shared amongst "mirror workers") 
ASSUME FiniteIndices ==
  \* Each (correct) validator has a finite set of workers.
  /\ IsFiniteSet(WorkerIndex)
  \* Each validator has at least one worker. 
  /\ WorkerIndex # {}

\* A specific worker has a worker 'index' is part of a 'val'idator 
Worker == [index : WorkerIndex, val : ByzValidator] 

(***************************************************************************)
(* There is a bijection between ByzValidators and Primaries.  For the sake *)
(* of simplicity, we identify them in the specification.                   *)
(***************************************************************************)

\* Each 'Primary' is identified with its whole validator node
Primary == ByzValidator 

\* end of "WORKER-PRIMARY DISTINCTION"

-----------------------------------------------------------------------------

(***************************************************************************)
(*                           ON BATCHES                                    *)
(***************************************************************************)

(*
We phrase the specification in terms of batches.
Single transactions will be covered in a refined spec.
*)

\* this is inherited from the top level spec
CONSTANT Payload

\* There are a countable number of requests to be served.
\* ASSUME AssumeCountablePayload == \E f \in Bijection(Payload, NN) : TRUE

\* the alsways usefule empty set
EmptySet == {}

\* We want to think of each payload as a batch
Batch == Payload

ReqConstr(r) == 
  /\ r \in [Worker -> ((SUBSET Batch) \ {EmptySet})]
  /\ \A w1,w2 \in Worker : w1 # w2 => r[w1] \cap r[w2] = {}
  /\ UNION { r[w] : w \in Worker } = Batch

PossibleRequests == 
  { r \in [Worker -> ((SUBSET Batch) \ {EmptySet})] : ReqConstr(r) }
  
\* compared to the top level spec, this is a refeinement of the state space
Request == CHOOSE r \in PossibleRequests : TRUE 

RequestUnion == UNION { Request[w] : w \in Worker }

-----------------------------------------------------------------------------

(***************************************************************************)
(*                             THE SPEC                                    *)
(***************************************************************************)

(***************************************************************************)
(* We use the very same idea of Lamport's consensus specification.  In     *)
(* particular, we do not yet require any DAG structure, but just a set of  *)
(* chosen batches, growing and eventually including all batches.           *)
(***************************************************************************)

N == Cardinality(Batch)

NN == 1..N

\* The _sequence_ of all batches that are chosen (at points in time).
VARIABLE chosenSet

\* A first approximation of chosenSet's type
TypeOK ==
  /\ chosenSet \in [NN -> SUBSET RequestUnion]
  /\ \A n \in NN : IsFiniteSet(chosenSet[n])

(***************************************************************************)
(* The 'Init' predicate describes the unique initial state of 'chosenSet'. *)
(***************************************************************************)

Init == 
  chosenSet = [n \in NN \cup {N + 1} |-> {}]

(***************************************************************************)
(* The next-state relation 'Next' describes how the variable 'chosenSet'   *)
(* can change from one step to the next.  Note that 'Next' is enabled      *)
(* (equals true for some next value chosenSet' of chosenSet) if and only   *)
(* if chosenSet equals the empty set.                                      *)
(***************************************************************************)


\* the "Next" action of workers w \in ws injecting (range of) Xs
Next(ws, Xs) == 
  \* type check
  /\ ws \in SUBSET Worker
  /\ Xs \in [ws -> (SUBSET RequestUnion) \ {EmptySet}]
  /\ \A w \in ws : /\ Xs[w] \subseteq Request[w]
                   /\ IsFiniteSet(Xs[w])
  /\ LET 
       newRequests == UNION Range(Xs)
     IN \E n \in NN:
        \* precondition
        /\ chosenSet[n] = {}
        /\ \A m \in NN : m < n => /\ chosenSet[m] # {} 
        /\ newRequests \cap UNION { chosenSet[k] : k \in 1..n } = EmptySet
        \* postcondition 
        /\ chosenSet' = [chosenSet EXCEPT ![n] = newRequests]


\* the infinite disjunction of all possible instances of the "Next" action
SomeNext == 
  \/ \E ws \in SUBSET Worker : 
     \E Xs \in [ws -> (SUBSET RequestUnion)]: 
       Next(ws, Xs)
  \/  /\ UNION { chosenSet[n] : n \in NN } = Batch
      /\ UNCHANGED chosenSet

(***************************************************************************)
(* The TLA+ temporal formula that specifies the system evolution.          *)
(***************************************************************************)

\* 
InclusionFairness ==
  \A ws \in SUBSET Worker :
  \A Xs \in [ws -> (SUBSET RequestUnion) \ {EmptySet}] :
     WF_chosenSet(Next(ws,Xs))

Spec == Init /\ [][SomeNext]_chosenSet /\ InclusionFairness

DONE == UNION { chosenSet[n] : n \in NN } = Batch

-----------------------------------------------------------------------------

(***************************************************************************)
(*                            Refinement                                   *)
(***************************************************************************)

MempoolProjection ==
  INSTANCE AbstractMempoolSpec WITH 
    mempool <- UNION { chosenSet[n] : n \in NN }

\* 
THEOREM Spec => MempoolProjection!Spec

=============================================================================
