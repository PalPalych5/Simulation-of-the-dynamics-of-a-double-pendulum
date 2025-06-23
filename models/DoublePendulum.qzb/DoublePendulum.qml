import QtQuick
import QtQuick3D

Node {
    id: node

    // Resources
    PrincipledMaterial {
        id: sharedPbrMaterial
        baseColor: "#b2b2b2"
        metalness: 1.0
        roughnessMap: Texture { source: "qrc:/textures/aluminum_roughness.png" }
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }

    // Nodes:
    Model {
        id: base
        objectName: "base"
        source: "meshes/head_mesh.mesh"
        materials: [
            sharedPbrMaterial
        ]
        Node {
            id: link1_Pivot
            objectName: "Link1_Pivot"
            position: Qt.vector3d(0, -10.6876, -266.398)
            Model {
                id: bob11
                objectName: "bob11"
                source: "meshes/pendulum_004_mesh.mesh"
                materials: [
                    sharedPbrMaterial
                ]
            }
            Node {
                id: link2_Pivot
                objectName: "Link2_Pivot"
                position: Qt.vector3d(0, -7.22452, 120.053)
                Model {
                    id: bob1
                    objectName: "bob1"
                    source: "meshes/pendulum_002_mesh.mesh"
                    materials: [
                        sharedPbrMaterial
                    ]
                }
                Model {
                    id: bob2
                    objectName: "bob2"
                    source: "meshes/pendulum_003_mesh.mesh"
                    materials: [
                        sharedPbrMaterial
                    ]
                }
                Model {
                    id: rod2
                    objectName: "rod2"
                    source: "meshes/pendulum_001_mesh.mesh"
                    materials: [
                        sharedPbrMaterial
                    ]
                }
            }
            Model {
                id: rod1
                objectName: "rod1"
                source: "meshes/pendulum_mesh.mesh"
                materials: [
                    sharedPbrMaterial
                ]
            }
            Model {
                id: top_
                objectName: "top"
                source: "meshes/pendulum_005_mesh.mesh"
                materials: [
                    sharedPbrMaterial
                ]
            }
        }
    }

    // Animations:
}
