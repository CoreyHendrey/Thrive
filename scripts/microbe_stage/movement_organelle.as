#include "organelle_component.as"
#include "microbe_operations.as"

// #define ANIMATE_FLAGELLA

// Enables a microbe to move and turn

// See organelle_component.as for more information about the
// organelle component methods and the arguments they receive.

// Calculate the momentum of the movement organelle based on angle towards nucleus
Float3 calculateForce(int q, int r, float momentum){
    Float3 organelle = Hex::axialToCartesian(q, r);
    Float3 nucleus = Hex::axialToCartesian(0, 0);
    auto delta = nucleus - organelle;
    return delta.Normalize() * momentum;
}

//! \todo flagellum animation
class MovementOrganelle : OrganelleComponent{

    // Constructor
    //
    // @param momentum
    //  The force this organelle can exert to move a microbe.
    //
    // @param torque
    //  The torque this organelle can exert to turn a microbe.
    MovementOrganelle(float momentum, float torque){

        // Store this here temporarily
        this.force = Float3(momentum);
        this.torque = torque;
    }

    void
    onAddedToMicrobe(
        ObjectID microbeEntity,
        int q, int r, int rotation,
        PlacedOrganelle@ organelle
    ) override {

        this.force = calculateForce(q, r, this.force.X);

        Float3 organellePos = Hex::axialToCartesian(q, r);
        Float3 nucleus = Hex::axialToCartesian(0, 0);
        auto delta = nucleus - organellePos;
        float angle = atan2(-delta.Z, delta.X);
        if(angle < 0){
            angle = angle + (2 * PI);
        }

        angle = ((angle * 180)/PI + 180) % 360;

        // This is already added by the PlacedOrganlle.onAddedToMicrobe
        Model@ model = organelle.world.GetComponent_Model(organelle.organelleEntity);

        if(model is null)
            assert(false, "MovementOrganelle added to Organelle that has no Model component");

        // The organelles' scenenode is positioned by itself unlike
        // the lua version where that was also attempted here

#if ANIMATE_FLAGELLA
        // Create animation component
        Animated@ animated = organelle.world.Create_Animated(organelle.organelleEntity,
            model.GraphicalObject);
        SimpleAnimation moveAnimation("Move");
        moveAnimation.Loop = true;
        // 0.25 is the "idle" animation speed when the flagellum isn't used
        moveAnimation.SpeedFactor = 0.25f;
        animated.AddAnimation(moveAnimation);
        // Don't forget to mark to apply the new animation
        animated.Marked = true;
#endif //ANIMATE_FLAGELLA

        // This is already applied
        // auto@ renderNode = organelle.world.GetComponent_RenderNode(organelle.organelleEntity);
        // renderNode.Node.setPosition(organellePos);
        // renderNode.Node.setOrientation(Ogre::Quaternion(Ogre::Degree(angle),
        //         Ogre::Vector3(0, 1, 0)));
    }

    // void MovementOrganelle.load(storage){
    // this.position = {}
    // this.energyMultiplier = storage.get("energyMultiplier", 0.025)
    // this.force = storage.get("force", Vector3(0,0,0))
    // this.torque = storage.get("torque", 500)
    // }

    // void MovementOrganelle.storage(){
    // auto storage = StorageContainer()
    // storage.set("energyMultiplier", this.energyMultiplier)
    // storage.set("force", this.force)
    // storage.set("torque", this.torque)
    // return storage
    // }

    Float3 calculateMovementForce(ObjectID microbeEntity, PlacedOrganelle@ organelle,
        int milliseconds, MicrobeComponent@ microbeComponent, Position@ pos
    ) {
        // The movementDirection is the player or AI input
        Float3 direction = microbeComponent.movementDirection;

#if ANIMATE_FLAGELLA
        // For changing animation speed
        Animated@ animated = organelle.world.GetComponent_Animated(organelle.organelleEntity);
#endif //ANIMATE_FLAGELLA
        
        auto forceMagnitude = this.force.Dot(direction);
        if(forceMagnitude > 0){
            if(direction.LengthSquared() < EPSILON || this.force.LengthSquared() < EPSILON){
                this.movingTail = false;
#if ANIMATE_FLAGELLA
                animated.GetAnimation(0).SpeedFactor = 0.25f;
#endif //ANIMATE_FLAGELLA
                return Float3(0, 0, 0);
            }

            this.movingTail = true;
#if ANIMATE_FLAGELLA
            animated.GetAnimation(0).SpeedFactor = 1.3;
#endif //ANIMATE_FLAGELLA
            // 5 per second per flagella (according to microbe descisions)
            double energy = abs(5.0f/milliseconds);

            auto availableEnergy = MicrobeOperations::takeCompound(organelle.world,
                microbeEntity, SimulationParameters::compoundRegistry().getTypeId("atp"),
                energy);

            if(availableEnergy < energy){
                forceMagnitude = sign(forceMagnitude) * availableEnergy * 1000.f /
                    milliseconds;
                this.movingTail = false;
#if ANIMATE_FLAGELLA
                animated.GetAnimation(0).SpeedFactor = 0.25f;
#endif //ANIMATE_FLAGELLA
            }

            float impulseMagnitude = (FLAGELLA_BASE_FORCE * microbeComponent.movementFactor *
                milliseconds * forceMagnitude) / 1000.f;

            // Rotate the 'thrust' based on our orientation
            direction = pos._Orientation.RotateVector(direction);

            // This isn't needed
            //direction.Y = 0;
            //direction = direction.Normalize();
            // Float3 impulse = direction * impulseMagnitude;
            return direction * impulseMagnitude /* impulse */;
        } else {
            if(this.movingTail){
                this.movingTail = false;
#if ANIMATE_FLAGELLA
                animated.GetAnimation(0).SpeedFactor = 0.25f;
#endif //ANIMATE_FLAGELLA
            }
        }

        return Float3(0, 0, 0);
    }

    void
    update(
        ObjectID microbeEntity,
        PlacedOrganelle@ organelle,
        int logicTime
    ) override {

        MicrobeComponent@ microbeComponent = cast<MicrobeComponent>(
            organelle.world.GetScriptComponentHolder("MicrobeComponent").Find(microbeEntity));
        auto pos = organelle.world.GetComponent_Position(microbeEntity);

        const auto force = calculateMovementForce(microbeEntity, organelle, logicTime,
            microbeComponent, pos);

        if(force != Float3(0, 0, 0))
            microbeComponent.addMovementForce(force);
    }

    private Float3 force;
    private float torque;
    // float backwards_multiplier = 0;
    private bool movingTail = false;
}
